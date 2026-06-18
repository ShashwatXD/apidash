import 'dart:io';

import 'package:apidash/services/storage/atomic_file_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const kSyncDeviceRelativePath = '.apidash/sync/device.json';

class SyncDeviceIdentity {
  const SyncDeviceIdentity({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.createdAt,
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String createdAt;

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'displayName': displayName,
        'platform': platform,
        'createdAt': createdAt,
      };

  factory SyncDeviceIdentity.fromJson(Map<String, Object?> json) {
    return SyncDeviceIdentity(
      deviceId: json['deviceId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'API Dash device',
      platform: json['platform'] as String? ?? Platform.operatingSystem,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}

class SyncDeviceStore {
  SyncDeviceStore(this.workspaceRoot);

  final String workspaceRoot;

  String get _devicePath => p.join(workspaceRoot, kSyncDeviceRelativePath);

  Future<SyncDeviceIdentity> getOrCreate({String? displayName}) async {
    final existing = await readJsonFile(_devicePath);
    if (existing != null) {
      return SyncDeviceIdentity.fromJson(existing);
    }

    final legacy = await _readLegacyIdentity();
    if (legacy != null) {
      await _writeIdentity(legacy);
      return legacy;
    }

    final identity = SyncDeviceIdentity(
      deviceId: 'dev-${const Uuid().v4()}',
      displayName: displayName ?? _defaultDisplayName(),
      platform: Platform.operatingSystem,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _writeIdentity(identity);
    return identity;
  }

  Future<void> _writeIdentity(SyncDeviceIdentity identity) async {
    final dir = Directory(p.dirname(_devicePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await writeJsonAtomic(_devicePath, identity.toJson());
  }

  Future<SyncDeviceIdentity?> _readLegacyIdentity() async {
    try {
      final support = await getApplicationSupportDirectory();
      final legacyPath = p.join(support.path, 'apidash', 'device.json');
      final json = await readJsonFile(legacyPath);
      if (json == null) return null;
      return SyncDeviceIdentity.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  String _defaultDisplayName() {
    final host = Platform.localHostname;
    if (host.isNotEmpty) return host;
    return 'API Dash ${Platform.operatingSystem}';
  }
}
