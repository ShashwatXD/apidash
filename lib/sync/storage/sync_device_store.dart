import 'dart:io';

import 'package:apidash/services/storage/atomic_file_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _deviceFileName = 'device.json';

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
  SyncDeviceStore({String? rootOverride}) : _rootOverride = rootOverride;

  final String? _rootOverride;

  Future<String> _rootDir() async {
    if (_rootOverride != null) return _rootOverride;
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'apidash');
  }

  Future<String> _deviceFilePath() async {
    return p.join(await _rootDir(), _deviceFileName);
  }

  Future<SyncDeviceIdentity> getOrCreate({String? displayName}) async {
    final path = await _deviceFilePath();
    final existing = await readJsonFile(path);
    if (existing != null) {
      return SyncDeviceIdentity.fromJson(existing);
    }

    final identity = SyncDeviceIdentity(
      deviceId: 'dev-${const Uuid().v4()}',
      displayName: displayName ?? _defaultDisplayName(),
      platform: Platform.operatingSystem,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await writeJsonAtomic(path, identity.toJson());
    return identity;
  }

  String _defaultDisplayName() {
    final host = Platform.localHostname;
    if (host.isNotEmpty) return host;
    return 'API Dash ${Platform.operatingSystem}';
  }
}
