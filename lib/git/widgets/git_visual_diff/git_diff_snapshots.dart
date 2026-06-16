import 'dart:convert';
import 'dart:io';

import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/services/git_service.dart';
import 'package:path/path.dart' as p;

class GitDiffSnapshots {
  const GitDiffSnapshots({
    this.headRaw,
    this.currentRaw,
    this.headJson,
    this.currentJson,
  });

  final String? headRaw;
  final String? currentRaw;
  final Map<String, Object?>? headJson;
  final Map<String, Object?>? currentJson;

  bool get hasContent =>
      _hasText(headRaw) ||
      _hasText(currentRaw) ||
      headJson != null ||
      currentJson != null;

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

Map<String, Object?>? parseJsonMap(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
  } catch (_) {}
  return null;
}

Future<GitDiffSnapshots> loadGitDiffSnapshots({
  required GitService git,
  required String workspacePath,
  required GitChange change,
}) async {
  final relativePath = change.path.replaceAll('\\', '/');
  String? headRaw;
  String? currentRaw;

  final isNew = change.type == GitChangeType.untracked ||
      change.type == GitChangeType.added;

  if (!isNew && change.type != GitChangeType.deleted) {
    headRaw = await git.showObject(workspacePath, 'HEAD:$relativePath');
  }

  if (change.type == GitChangeType.deleted) {
    headRaw ??= await git.showObject(workspacePath, 'HEAD:$relativePath');
  } else {
    final file = File(p.join(workspacePath, relativePath));
    if (await file.exists()) {
      currentRaw = await file.readAsString();
    }
  }

  // Staged-only changes: working tree matches HEAD but index differs.
  if (!isNew && change.type != GitChangeType.deleted) {
    final indexRaw = await git.showObject(workspacePath, ':$relativePath');
    if (indexRaw != null && indexRaw.trim().isNotEmpty) {
      if (headRaw == null || headRaw == currentRaw) {
        if (indexRaw != headRaw) {
          currentRaw = indexRaw;
        }
      }
    }
  }

  return GitDiffSnapshots(
    headRaw: headRaw,
    currentRaw: currentRaw,
    headJson: parseJsonMap(headRaw),
    currentJson: parseJsonMap(currentRaw),
  );
}

String prettyJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  try {
    final decoded = jsonDecode(raw);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return raw;
  }
}
