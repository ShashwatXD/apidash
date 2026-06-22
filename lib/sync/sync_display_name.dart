import 'dart:io';

import 'consts.dart';

String syncLocalDisplayName() {
  final host = Platform.localHostname;
  if (host.isNotEmpty) return host;
  return '$kSyncFallbackDisplayNamePrefix ${Platform.operatingSystem}';
}
