import 'dart:convert';
import 'dart:io';

import 'package:apidash/services/storage/atomic_file_io.dart';
import 'package:path/path.dart' as p;

import 'sync_file_filter.dart';

String workspaceFilePath(String workspaceRoot, String relativePath) {
  return p.join(workspaceRoot, relativePath.replaceAll('/', p.separator));
}

Future<String?> readSyncableWorkspaceFile(
  String workspaceRoot,
  String relativePath,
) async {
  if (!isSyncablePath(relativePath)) return null;
  return readFileString(workspaceFilePath(workspaceRoot, relativePath));
}

Future<void> writeSyncableWorkspaceFile(
  String workspaceRoot,
  String relativePath,
  String content,
) async {
  if (!isSyncablePath(relativePath)) {
    throw StateError('Path is not syncable: $relativePath');
  }
  await writeFileAtomic(
    workspaceFilePath(workspaceRoot, relativePath),
    utf8.encode(content),
  );
}

Future<void> deleteSyncableWorkspaceFile(
  String workspaceRoot,
  String relativePath,
) async {
  if (!isSyncablePath(relativePath)) {
    throw StateError('Path is not syncable: $relativePath');
  }
  final file = File(workspaceFilePath(workspaceRoot, relativePath));
  if (await file.exists()) {
    await file.delete();
  }
}
