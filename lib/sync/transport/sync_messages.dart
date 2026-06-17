import 'dart:convert';

/// Wire protocol for the LAN sync session.
///
/// Messages are JSON objects exchanged over a single WebSocket. Each message
/// carries a [SyncMessageType] under the `type` key. The host (desktop) is the
/// server; the phone is the client (Phase B).
const kSyncProtocolVersion = 1;

/// Default loopback-safe port range the host tries to bind to.
const kSyncDefaultPort = 4571;

enum SyncMessageType {
  hello,
  helloAck,
  manifest,
  fileRequest,
  fileContent,
  applyComplete,
  error,
  bye,
}

extension SyncMessageTypeWire on SyncMessageType {
  String get wire => name;

  static SyncMessageType? fromWire(String? value) {
    for (final type in SyncMessageType.values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

/// A parsed envelope `{ "type": ..., "payload": {...} }`.
class SyncMessage {
  const SyncMessage(this.type, [this.payload = const {}]);

  final SyncMessageType type;
  final Map<String, Object?> payload;

  String encode() => jsonEncode({
        'type': type.wire,
        'payload': payload,
      });

  static SyncMessage? tryDecode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final type = SyncMessageTypeWire.fromWire(decoded['type'] as String?);
    if (type == null) return null;
    final payload = decoded['payload'];
    return SyncMessage(
      type,
      payload is Map
          ? payload.map((key, value) => MapEntry('$key', value))
          : const {},
    );
  }

  /// Client → host: introduces the peer and proves it holds the QR token.
  factory SyncMessage.hello({
    required String token,
    required String deviceId,
    required String displayName,
    required String syncWorkspaceId,
  }) {
    return SyncMessage(SyncMessageType.hello, {
      'protocolVersion': kSyncProtocolVersion,
      'token': token,
      'deviceId': deviceId,
      'displayName': displayName,
      'syncWorkspaceId': syncWorkspaceId,
    });
  }

  /// Host → client: confirms the handshake and shares the host identity.
  factory SyncMessage.helloAck({
    required String deviceId,
    required String displayName,
    required String syncWorkspaceId,
  }) {
    return SyncMessage(SyncMessageType.helloAck, {
      'protocolVersion': kSyncProtocolVersion,
      'deviceId': deviceId,
      'displayName': displayName,
      'syncWorkspaceId': syncWorkspaceId,
    });
  }

  /// Either side: the syncable file manifest `{ relativePath: sha256:... }`.
  factory SyncMessage.manifest(Map<String, String> files) {
    return SyncMessage(SyncMessageType.manifest, {'files': files});
  }

  /// Request file bytes for [path] from the peer.
  factory SyncMessage.fileRequest(String path) {
    return SyncMessage(SyncMessageType.fileRequest, {'path': path});
  }

  /// Response carrying workspace file content or a deletion marker.
  factory SyncMessage.fileContent({
    required String path,
    String? content,
    bool deleted = false,
  }) {
    return SyncMessage(SyncMessageType.fileContent, {
      'path': path,
      'content': ?content,
      'deleted': deleted,
    });
  }

  factory SyncMessage.applyComplete(
    Map<String, String> files, {
    Map<String, String> writes = const {},
    List<String> deletes = const [],
  }) {
    return SyncMessage(SyncMessageType.applyComplete, {
      'files': files,
      'writes': writes,
      'deletes': deletes,
    });
  }

  factory SyncMessage.error(String message) {
    return SyncMessage(SyncMessageType.error, {'message': message});
  }

  factory SyncMessage.bye([String? reason]) {
    return SyncMessage(SyncMessageType.bye, {
      'reason': ?reason,
    });
  }

  Map<String, String> readManifest() => _readStringMap('files');

  Map<String, String> readWrites() => _readStringMap('writes');

  List<String> readDeletes() {
    final raw = payload['deletes'];
    if (raw is List) {
      return raw.map((e) => '$e').toList();
    }
    return const [];
  }

  Map<String, String> _readStringMap(String key) {
    final value = payload[key];
    final result = <String, String>{};
    if (value is Map) {
      for (final entry in value.entries) {
        result['${entry.key}'] = '${entry.value}';
      }
    }
    return result;
  }

  String? get stringToken => payload['token'] as String?;
  String? get stringDeviceId => payload['deviceId'] as String?;
  String? get stringDisplayName => payload['displayName'] as String?;
  String? get stringSyncWorkspaceId => payload['syncWorkspaceId'] as String?;
  String? get errorMessage => payload['message'] as String?;
  String? get stringPath => payload['path'] as String?;
  String? get stringContent => payload['content'] as String?;
  bool get isDeleted => payload['deleted'] == true;
}

/// Payload encoded into the QR code shown on the desktop host. The phone scans
/// this to learn where to connect and which one-time token to present.
class SyncQrPayload {
  const SyncQrPayload({
    required this.host,
    required this.port,
    required this.token,
    required this.syncWorkspaceId,
    required this.hostDeviceId,
    required this.hostDisplayName,
  });

  final String host;
  final int port;
  final String token;
  final String syncWorkspaceId;
  final String hostDeviceId;
  final String hostDisplayName;

  String get websocketUrl => 'ws://$host:$port/sync';

  String encode() => jsonEncode({
        'v': kSyncProtocolVersion,
        'host': host,
        'port': port,
        'token': token,
        'syncWorkspaceId': syncWorkspaceId,
        'hostDeviceId': hostDeviceId,
        'hostDisplayName': hostDisplayName,
      });

  static SyncQrPayload? tryDecode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final host = decoded['host'] as String?;
    final port = decoded['port'];
    final token = decoded['token'] as String?;
    if (host == null || token == null || port is! int) return null;
    return SyncQrPayload(
      host: host,
      port: port,
      token: token,
      syncWorkspaceId: decoded['syncWorkspaceId'] as String? ?? '',
      hostDeviceId: decoded['hostDeviceId'] as String? ?? '',
      hostDisplayName: decoded['hostDisplayName'] as String? ?? '',
    );
  }
}
