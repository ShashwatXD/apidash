import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../consts.dart';
import '../models/sync_models.dart';
import '../storage/peer_sync_store.dart';
import '../storage/sync_device_store.dart';
import '../sync_diff.dart';
import '../sync_workspace_io.dart';
import 'sync_file_transfer.dart';
import 'sync_messages.dart';

enum SyncServerStatus {
  idle,
  listening,
  connected,
  error,
}

/// Desktop-side LAN sync host.
class SyncSessionServer implements SyncFileTransfer {
  SyncSessionServer({
    required this.identity,
    required this.workspaceMeta,
    required this.localManifest,
    required this.peerStore,
    required this.workspaceRoot,
    int? port,
    Random? random,
    Duration? sessionTimeout,
  })  : _preferredPort = port ?? kSyncDefaultPort,
        _sessionTimeout = sessionTimeout ?? kSyncSessionTimeout,
        token = _generateToken(random ?? Random.secure());

  final SyncDeviceIdentity identity;
  final SyncWorkspaceMeta workspaceMeta;
  final Map<String, String> localManifest;
  final PeerSyncStore peerStore;
  final String workspaceRoot;
  final String token;

  final int _preferredPort;
  final Duration _sessionTimeout;

  HttpServer? _httpServer;
  WebSocket? _activeSocket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _sessionTimer;

  String? _hostAddress;
  int? _boundPort;
  SyncServerStatus _status = SyncServerStatus.idle;
  Map<String, String> _peerManifest = const {};
  SyncPeerInfo? _activePeer;
  final Map<String, String?> _peerFileCache = {};
  final Map<String, Completer<_PeerFileResult>> _pendingPeerFiles = {};

  SyncServerStatus get status => _status;
  String? get hostAddress => _hostAddress;
  int? get boundPort => _boundPort;
  bool get isConnected => _activeSocket != null;
  Map<String, String> get peerManifest => _peerManifest;

  void Function(SyncPeerInfo peer, bool wasPairedBefore)? onPeerConnected;
  void Function()? onPeerDisconnected;
  void Function(SyncChangeSet changeSet)? onChangeSet;
  void Function(String message)? onError;
  void Function()? onSessionExpired;

  Future<SyncQrPayload?> start() async {
    if (_status != SyncServerStatus.idle) return qrPayload;
    final address = await resolveLanIpv4();
    if (address == null) {
      _status = SyncServerStatus.error;
      onError?.call(kErrSyncNoNetwork);
      return null;
    }
    _hostAddress = address;

    try {
      _httpServer = await _bind();
    } on SocketException catch (e) {
      _status = SyncServerStatus.error;
      onError?.call('$kErrSyncServerStart (${e.message})');
      return null;
    }

    _boundPort = _httpServer!.port;
    _status = SyncServerStatus.listening;
    _startSessionTimer();
    _httpServer!.listen(_handleRequest, onError: (Object e) {
      onError?.call('Sync server error: $e');
    });
    return qrPayload;
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(_sessionTimeout, () {
      onSessionExpired?.call();
      unawaited(stop());
    });
  }

  Future<HttpServer> _bind() async {
    try {
      return await HttpServer.bind(InternetAddress.anyIPv4, _preferredPort);
    } on SocketException {
      return HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
  }

  SyncQrPayload? get qrPayload {
    final host = _hostAddress;
    final port = _boundPort;
    if (host == null || port == null) return null;
    return SyncQrPayload(
      host: host,
      port: port,
      token: token,
      syncWorkspaceId: workspaceMeta.syncWorkspaceId,
      hostDeviceId: identity.deviceId,
      hostDisplayName: identity.displayName,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/sync' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    if (_activeSocket != null) {
      request.response.statusCode = HttpStatus.conflict;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    _attachSocket(socket);
  }

  void _attachSocket(WebSocket socket) {
    _activeSocket = socket;
    String? peerDeviceId;
    SyncPeerInfo? peer;

    _socketSub = socket.listen(
      (dynamic data) async {
        if (data is! String) return;
        final message = SyncMessage.tryDecode(data);
        if (message == null) return;

        switch (message.type) {
          case SyncMessageType.hello:
            if (message.stringToken != token) {
              _send(SyncMessage.error('Invalid or expired token'));
              await _closeSocket(notify: false);
              return;
            }
            peerDeviceId = message.stringDeviceId;
            peer = SyncPeerInfo(
              deviceId: message.stringDeviceId ?? '',
              displayName: message.stringDisplayName ?? 'Phone',
              syncWorkspaceId: message.stringSyncWorkspaceId ?? '',
            );
            _activePeer = peer;
            final wasPaired = await peerStore.hasPaired(
              peer!.deviceId,
              workspaceMeta.syncWorkspaceId,
            );
            _send(SyncMessage.helloAck(
              deviceId: identity.deviceId,
              displayName: identity.displayName,
              syncWorkspaceId: workspaceMeta.syncWorkspaceId,
            ));
            _send(SyncMessage.manifest(localManifest));
            onPeerConnected?.call(peer!, wasPaired);
            _status = SyncServerStatus.connected;
            break;
          case SyncMessageType.manifest:
            if (peer == null) {
              _send(SyncMessage.error('Handshake required before manifest'));
              return;
            }
            _peerManifest = message.readManifest();
            await _computeAndEmit(peerDeviceId: peerDeviceId);
            break;
          case SyncMessageType.fileRequest:
            await _handlePeerFileRequest(message.stringPath);
            break;
          case SyncMessageType.fileContent:
            _resolvePeerFile(message);
            break;
          case SyncMessageType.applyComplete:
            final manifest = message.readManifest();
            if (_activePeer != null && manifest.isNotEmpty) {
              await _persistBaseline(_activePeer!, manifest);
              await _computeAndEmit(peerDeviceId: peerDeviceId);
            }
            break;
          case SyncMessageType.bye:
            await _closeSocket();
            break;
          case SyncMessageType.error:
            onError?.call(message.errorMessage ?? 'Phone reported an error');
            break;
          case SyncMessageType.helloAck:
            break;
        }
      },
      onDone: () => _closeSocket(),
      onError: (Object e) {
        onError?.call('Connection error: $e');
        _closeSocket();
      },
      cancelOnError: true,
    );
  }

  Future<void> _handlePeerFileRequest(String? path) async {
    if (path == null || path.isEmpty) return;
    final content = await readSyncableWorkspaceFile(workspaceRoot, path);
    if (content == null) {
      _send(SyncMessage.fileContent(path: path, deleted: true));
      return;
    }
    _send(SyncMessage.fileContent(path: path, content: content));
  }

  void _resolvePeerFile(SyncMessage message) {
    final path = message.stringPath;
    if (path == null || path.isEmpty) return;
    final result = _PeerFileResult(
      content: message.isDeleted ? null : message.stringContent,
      deleted: message.isDeleted,
    );
    _peerFileCache[path] = result.content;
    _pendingPeerFiles.remove(path)?.complete(result);
  }

  @override
  Future<String?> fetchPeerFile(
    String path, {
    Duration timeout = kSyncFileRequestTimeout,
  }) async {
    if (_peerFileCache.containsKey(path)) {
      return _peerFileCache[path];
    }
    if (_activeSocket == null) return null;

    final completer = Completer<_PeerFileResult>();
    _pendingPeerFiles[path] = completer;
    _send(SyncMessage.fileRequest(path));

    try {
      final result = await completer.future.timeout(timeout);
      if (result.deleted) return null;
      return result.content;
    } on TimeoutException {
      _pendingPeerFiles.remove(path);
      return null;
    }
  }

  @override
  Future<void> sendLocalFile(String path, String content) async {
    _send(SyncMessage.fileContent(path: path, content: content));
  }

  @override
  Future<void> sendDeletedFile(String path) async {
    _send(SyncMessage.fileContent(path: path, deleted: true));
  }

  @override
  Future<void> sendApplyComplete(Map<String, String> manifest) async {
    _send(SyncMessage.applyComplete(manifest));
  }

  Future<void> _computeAndEmit({required String? peerDeviceId}) async {
    Map<String, String> baseline = const {};
    if (peerDeviceId != null && peerDeviceId.isNotEmpty) {
      final record = await peerStore.getPeer(peerDeviceId);
      if (record != null &&
          record.syncWorkspaceId == workspaceMeta.syncWorkspaceId) {
        baseline = record.files;
      }
    }

    if (_manifestsEqual(localManifest, _peerManifest)) {
      final peer = _activePeer;
      if (peer != null) {
        await _persistBaseline(peer, localManifest);
      }
      onChangeSet?.call(const SyncChangeSet());
      return;
    }

    final changeSet = baseline.isEmpty
        ? computeTransferChangeSet(local: localManifest, peer: _peerManifest)
        : computeSyncChangeSet(
            baseline: baseline,
            local: localManifest,
            peer: _peerManifest,
          );
    onChangeSet?.call(changeSet);
  }

  Future<void> _persistBaseline(
    SyncPeerInfo peer,
    Map<String, String> files,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await peerStore.getPeer(peer.deviceId);
    await peerStore.savePeer(
      PeerSyncRecord(
        peerDeviceId: peer.deviceId,
        peerDisplayName: peer.displayName,
        syncWorkspaceId: workspaceMeta.syncWorkspaceId,
        firstPairedAt: existing?.firstPairedAt ?? now,
        lastSyncAt: now,
        lastMode: existing == null ? 'transfer' : 'sync',
        files: files,
      ),
    );
  }

  bool _manifestsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _send(SyncMessage message) {
    _activeSocket?.add(message.encode());
  }

  Future<void> _closeSocket({bool notify = true}) async {
    final socket = _activeSocket;
    _activeSocket = null;
    _activePeer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    if (socket != null) {
      await socket.close();
    }
    for (final pending in _pendingPeerFiles.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Connection closed'));
      }
    }
    _pendingPeerFiles.clear();
    if (_status == SyncServerStatus.connected) {
      _status = SyncServerStatus.listening;
    }
    if (notify) onPeerDisconnected?.call();
  }

  Future<void> stop() async {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    await _closeSocket(notify: false);
    await _httpServer?.close(force: true);
    _httpServer = null;
    _status = SyncServerStatus.idle;
  }
}

class _PeerFileResult {
  const _PeerFileResult({required this.content, required this.deleted});

  final String? content;
  final bool deleted;
}

String _generateToken(Random random) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
}

Future<String?> resolveLanIpv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    String? fallback;
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        final ip = addr.address;
        if (addr.isLoopback) continue;
        if (ip.startsWith('169.254.')) continue;
        if (_isPrivateIpv4(ip)) return ip;
        fallback ??= ip;
      }
    }
    return fallback;
  } on SocketException {
    return null;
  }
}

bool _isPrivateIpv4(String ip) {
  if (ip.startsWith('10.') || ip.startsWith('192.168.')) return true;
  if (ip.startsWith('172.')) {
    final second = int.tryParse(ip.split('.').elementAt(1)) ?? 0;
    return second >= 16 && second <= 31;
  }
  return false;
}
