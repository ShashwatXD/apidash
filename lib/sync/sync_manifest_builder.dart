import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'sync_file_filter.dart';

String hashFileContent(List<int> bytes) {
  return 'sha256:${sha256.convert(bytes).toString()}';
}

Future<String> hashFileAtPath(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  return hashFileContent(bytes);
}

Future<Map<String, String>> buildSyncManifest(String workspaceRoot) async {
  final root = Directory(workspaceRoot);
  if (!await root.exists()) {
    return {};
  }

  final manifest = <String, String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p
        .relative(entity.path, from: workspaceRoot)
        .replaceAll('\\', '/');
    if (!isSyncablePath(relative)) continue;
    manifest[relative] = await hashFileAtPath(entity.path);
  }
  return Map.fromEntries(
    manifest.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}
