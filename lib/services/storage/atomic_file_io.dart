import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'disk_sync.dart';

Future<void> _ensureDirectory(Directory dir) async {
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}

Future<void> writeFileAtomic(String path, List<int> bytes) async {
  final file = File(path);
  final parent = file.parent;
  await _ensureDirectory(parent);

  final tmpPath = '$path.tmp';
  final tmpFile = File(tmpPath);
  workspaceWriteJournal.record(tmpPath);
  workspaceWriteJournal.record(path);
  try {
    await tmpFile.writeAsBytes(bytes, flush: true);
    await _ensureDirectory(parent);
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(path);
    workspaceWriteJournal.record(path);
  } on FileSystemException catch (e) {
    // Retry once when a concurrent folder rename/remove raced the write.
    if (e.osError?.errorCode == 2 && await tmpFile.exists()) {
      try {
        await _ensureDirectory(parent);
        if (await file.exists()) {
          await file.delete();
        }
        await tmpFile.rename(path);
        workspaceWriteJournal.record(path);
        return;
      } catch (retryError, retrySt) {
        debugPrint('writeFileAtomic retry failed for $path: $retryError\n$retrySt');
      }
    }
    debugPrint('writeFileAtomic failed for $path: $e');
    if (await tmpFile.exists()) {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
    rethrow;
  } catch (e, st) {
    debugPrint('writeFileAtomic failed for $path: $e\n$st');
    if (await tmpFile.exists()) {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
    rethrow;
  }
}

Future<void> writeJsonAtomic(String path, Map<String, Object?> json) async {
  final encoded = const JsonEncoder.withIndent('  ').convert(json);
  await writeFileAtomic(path, utf8.encode(encoded));
}

Future<String?> readFileString(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  return file.readAsString();
}

Future<Map<String, Object?>?> readJsonFile(String path) async {
  final raw = await readFileString(path);
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    return null;
  }
  return Map<String, Object?>.from(decoded);
}
