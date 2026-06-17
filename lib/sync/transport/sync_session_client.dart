import 'dart:async';
import 'dart:io';

import '../consts.dart';
import '../models/sync_models.dart';
import '../storage/peer_sync_store.dart';
import '../storage/sync_device_store.dart';
import '../sync_diff.dart';
import '../sync_workspace_io.dart';
import 'sync_file_transfer.dart';
import 'sync_messages.dart';

enum SyncClientStatus {
  idle,
  connecting,
  connected,
  error,
}

/// Mobile-side WebSocket client that connects to a desktop sync host.
class SyncSessionClient implements SyncFileTransfer {
  SyncSessionClient({
    required this.identity,
    required this.workspaceMeta,
    required this.localManifest,
    required this.peerStore,
    required this.workspaceRoot,
    required this.qrPayload,
  });

  final SyncDeviceIdentity identity;
  final SyncWorkspaceMeta workspaceMeta;
  final Map<String, String> localManifest;
  final PeerSyncStore peerStore;
  final String workspaceRoot;
  final SyncQrPayload qrPayload;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;

  SyncClientStatus _status = SyncClientStatus.idle;
  Map<String, String> _hostManifest = const {};
  final Map<String, String?> _hostFileCache = {};
  final Map<String, Completer<_HostFileResult>> _pendingHostFiles = {};

  SyncPeerInfo? _hostPeer;
  bool _wasPairedBefore = false;

  SyncClientStatus get status => _status;
  bool get isConnected => _socket != null && _status == SyncClientStatus.connected;
  SyncPeerInfo? get hostPeer => _hostPeer;
  bool get wasPairedBefore => _wasPairedBefore;

  void Function(SyncPeerInfo host, bool wasPairedBefore)? onHostConnected;
  void Function()? onHostDisconnected;
  void Function(SyncChangeSet changeSet)? onChangeSet;
  void Function(String message)? onError;

  Future<void> connect() async {
    if (_status != SyncClientStatus.idle) return;
    _status = SyncClientStatus.connecting;

    try {
      _socket = await WebSocket.connect(qrPayload.websocketUrl);
    } catch (e) {
      _status = SyncClientStatus.error;
      onError?.call('Could not connect to desktop: $e');
      return;
    }

    _attachSocket();
    _send(
      SyncMessage.hello(
        token: qrPayload.token,
        deviceId: identity.deviceId,
        displayName: identity.displayName,
        syncWorkspaceId: workspaceMeta.syncWorkspaceId,
      ),
    );
  }

  void _attachSocket() {
    _socketSub = _socket!.listen(
      (dynamic data) async {
        if (data is! String) return;
        final message = SyncMessage.tryDecode(data);
        if (message == null) return;

        switch (message.type) {
          case SyncMessageType.helloAck:
            _hostPeer = SyncPeerInfo(
              deviceId: message.stringDeviceId ?? qrPayload.hostDeviceId,
              displayName: message.stringDisplayName ?? qrPayload.hostDisplayName,
              syncWorkspaceId:
                  message.stringSyncWorkspaceId ?? qrPayload.syncWorkspaceId,
            );
            _wasPairedBefore = await peerStore.hasPaired(
              _hostPeer!.deviceId,
              _hostPeer!.syncWorkspaceId,
            );
            onHostConnected?.call(_hostPeer!, _wasPairedBefore);
            break;
          case SyncMessageType.manifest:
            _hostManifest = message.readManifest();
            _send(SyncMessage.manifest(localManifest));
            await _computeAndEmit();
            _status = SyncClientStatus.connected;
            break;
          case SyncMessageType.fileRequest:
            await _handleHostFileRequest(message.stringPath);
            break;
          case SyncMessageType.fileContent:
            _resolveHostFile(message);
            break;
          case SyncMessageType.applyComplete:
            final manifest = message.readManifest();
            if (_hostPeer != null && manifest.isNotEmpty) {
              await _persistBaseline(manifest);
            }
            break;
          case SyncMessageType.error:
            onError?.call(message.errorMessage ?? 'Desktop reported an error');
            break;
          case SyncMessageType.bye:
            await disconnect();
            break;
          case SyncMessageType.hello:
            break;
        }
      },
      onDone: () => disconnect(),
      onError: (Object e) {
        onError?.call('Connection error: $e');
        disconnect();
      },
      cancelOnError: true,
    );
  }

  Future<void> _handleHostFileRequest(String? path) async {
    if (path == null || path.isEmpty) return;
    final content = await readSyncableWorkspaceFile(workspaceRoot, path);
    if (content == null) {
      _send(SyncMessage.fileContent(path: path, deleted: true));
      return;
    }
    _send(SyncMessage.fileContent(path: path, content: content));
  }

  void _resolveHostFile(SyncMessage message) {
    final path = message.stringPath;
    if (path == null || path.isEmpty) return;
    final result = _HostFileResult(
      content: message.isDeleted ? null : message.stringContent,
      deleted: message.isDeleted,
    );
    _hostFileCache[path] = result.content;
    _pendingHostFiles.remove(path)?.complete(result);
  }

  @override
  Future<String?> fetchPeerFile(
    String path, {
    Duration timeout = kSyncFileRequestTimeout,
  }) async {
    if (_hostFileCache.containsKey(path)) {
      return _hostFileCache[path];
    }
    if (_socket == null) return null;

    final completer = Completer<_HostFileResult>();
    _pendingHostFiles[path] = completer;
    _send(SyncMessage.fileRequest(path));

    try {
      final result = await completer.future.timeout(timeout);
      if (result.deleted) return null;
      return result.content;
    } on TimeoutException {
      _pendingHostFiles.remove(path);
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

  Future<void> _computeAndEmit() async {
    final host = _hostPeer;
    if (host == null) return;

    Map<String, String> baseline = const {};
    final record = await peerStore.getPeer(host.deviceId);
    if (record != null && record.syncWorkspaceId == host.syncWorkspaceId) {
      baseline = record.files;
    }

    if (_manifestsEqual(localManifest, _hostManifest)) {
      await _persistBaseline(localManifest);
      onChangeSet?.call(const SyncChangeSet());
      return;
    }

    final changeSet = baseline.isEmpty
        ? computeTransferChangeSet(local: localManifest, peer: _hostManifest)
        : computeSyncChangeSet(
            baseline: baseline,
            local: localManifest,
            peer: _hostManifest,
          );
    onChangeSet?.call(changeSet);
  }

  bool _manifestsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  Future<void> _persistBaseline(Map<String, String> files) async {
    final host = _hostPeer;
    if (host == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await peerStore.getPeer(host.deviceId);
    await peerStore.savePeer(
      PeerSyncRecord(
        peerDeviceId: host.deviceId,
        peerDisplayName: host.displayName,
        syncWorkspaceId: host.syncWorkspaceId,
        firstPairedAt: existing?.firstPairedAt ?? now,
        lastSyncAt: now,
        lastMode: existing == null ? 'transfer' : 'sync',
        files: files,
      ),
    );
  }

  void _send(SyncMessage message) {
    _socket?.add(message.encode());
  }

  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    await _socketSub?.cancel();
    _socketSub = null;
    if (socket != null) {
      await socket.close();
    }
    for (final pending in _pendingHostFiles.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Connection closed'));
      }
    }
    _pendingHostFiles.clear();
    if (_status == SyncClientStatus.connected) {
      _status = SyncClientStatus.idle;
    }
    onHostDisconnected?.call();
  }
}

class _HostFileResult {
  const _HostFileResult({required this.content, required this.deleted});

  final String? content;
  final bool deleted;
}
