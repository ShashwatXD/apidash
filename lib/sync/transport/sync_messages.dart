import 'dart:convert';

import '../consts.dart';

/// Wire protocol for the LAN sync session.
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

  factory SyncMessage.hello({
    required String token,
    required String workspaceId,
    required String displayName,
    bool hasBaseline = false,
    String? sessionMode,
  }) {
    return SyncMessage(SyncMessageType.hello, {
      'protocolVersion': kSyncProtocolVersion,
      'token': token,
      'workspaceId': workspaceId,
      'displayName': displayName,
      'hasBaseline': hasBaseline,
      if (sessionMode != null) 'sessionMode': sessionMode,
    });
  }

  factory SyncMessage.helloAck({
    required String workspaceId,
    required String workspaceName,
    required String displayName,
    bool hasBaseline = false,
  }) {
    return SyncMessage(SyncMessageType.helloAck, {
      'protocolVersion': kSyncProtocolVersion,
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'displayName': displayName,
      'hasBaseline': hasBaseline,
    });
  }

  factory SyncMessage.manifest(Map<String, String> files) {
    return SyncMessage(SyncMessageType.manifest, {'files': files});
  }

  factory SyncMessage.fileRequest(String path) {
    return SyncMessage(SyncMessageType.fileRequest, {'path': path});
  }

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
    return SyncMessage(SyncMessageType.bye, {'reason': ?reason});
  }

  Map<String, String> readManifest() => _readStringMap('files');
  Map<String, String> readWrites() => _readStringMap('writes');

  List<String> readDeletes() {
    final raw = payload['deletes'];
    if (raw is List) return raw.map((e) => '$e').toList();
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
  String? get stringWorkspaceId => payload['workspaceId'] as String?;
  String? get stringSessionMode => payload['sessionMode'] as String?;
  String? get stringWorkspaceName => payload['workspaceName'] as String?;
  String? get stringDisplayName => payload['displayName'] as String?;
  bool get hasBaseline => payload['hasBaseline'] == true;
  String? get errorMessage => payload['message'] as String?;
  String? get stringPath => payload['path'] as String?;
  String? get stringContent => payload['content'] as String?;
  bool get isDeleted => payload['deleted'] == true;
}

class SyncQrPayload {
  const SyncQrPayload({
    required this.host,
    required this.port,
    required this.token,
    required this.workspaceId,
    required this.workspaceName,
    required this.desktopName,
  });

  final String host;
  final int port;
  final String token;
  final String workspaceId;
  final String workspaceName;
  final String desktopName;

  String get websocketUrl => 'ws://$host:$port$kSyncWebSocketPath';

  String encode() => jsonEncode({
        'v': kSyncProtocolVersion,
        'host': host,
        'port': port,
        'token': token,
        'workspaceId': workspaceId,
        'workspaceName': workspaceName,
        'desktopName': desktopName,
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
      workspaceId: decoded['workspaceId'] as String? ?? '',
      workspaceName: decoded['workspaceName'] as String? ?? '',
      desktopName: decoded['desktopName'] as String? ?? '',
    );
  }
}
