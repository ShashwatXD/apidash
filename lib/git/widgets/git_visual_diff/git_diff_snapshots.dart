import 'dart:convert';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/services/git_service.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_diff_file_kind.dart';
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
  if (gitDiffIsResponseBodyFile(relativePath)) {
    return _loadResponseBodyFileSnapshots(
      git: git,
      workspacePath: workspacePath,
      change: change,
      relativePath: relativePath,
    );
  }

  String? headRaw;
  String? currentRaw;

  final isNew =
      change.type == GitChangeType.untracked ||
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

  final parsedHeadJson = parseJsonMap(headRaw);
  final parsedCurrentJson = parseJsonMap(currentRaw);

  return GitDiffSnapshots(
    headRaw: headRaw,
    currentRaw: currentRaw,
    headJson: _inlineWorkspaceResponseBodyFile(
      json: parsedHeadJson,
      workspacePath: workspacePath,
      relativePath: relativePath,
    ),
    currentJson: _inlineWorkspaceResponseBodyFile(
      json: parsedCurrentJson,
      workspacePath: workspacePath,
      relativePath: relativePath,
    ),
  );
}

Future<GitDiffSnapshots> _loadResponseBodyFileSnapshots({
  required GitService git,
  required String workspacePath,
  required GitChange change,
  required String relativePath,
}) async {
  final responseRelativePath = p
      .join(p.dirname(relativePath), kWorkspaceResponseFile)
      .replaceAll('\\', '/');
  final isNew =
      change.type == GitChangeType.untracked ||
      change.type == GitChangeType.added;

  String? headRaw;
  String? currentRaw;

  if (!isNew && change.type != GitChangeType.deleted) {
    headRaw = await git.showObject(workspacePath, 'HEAD:$responseRelativePath');
  }
  if (change.type == GitChangeType.deleted) {
    headRaw ??= await git.showObject(
      workspacePath,
      'HEAD:$responseRelativePath',
    );
  } else {
    final responseFile = File(p.join(workspacePath, responseRelativePath));
    if (await responseFile.exists()) {
      currentRaw = await responseFile.readAsString();
    }
  }

  if (!isNew && change.type != GitChangeType.deleted) {
    final indexRaw = await git.showObject(
      workspacePath,
      ':$responseRelativePath',
    );
    if (indexRaw != null && indexRaw.trim().isNotEmpty) {
      if (headRaw == null || headRaw == currentRaw) {
        if (indexRaw != headRaw) {
          currentRaw = indexRaw;
        }
      }
    }
  }

  final headBytes = !isNew
      ? await git.showObjectBytes(workspacePath, 'HEAD:$relativePath')
      : null;
  final currentBytes = change.type == GitChangeType.deleted
      ? null
      : await _readCurrentResponseBodyBytes(
          git: git,
          workspacePath: workspacePath,
          relativePath: relativePath,
          headBytes: headBytes,
          isNew: isNew,
        );

  return GitDiffSnapshots(
    headRaw: headRaw,
    currentRaw: currentRaw,
    headJson: _withResponseBodyBytes(
      parseJsonMap(headRaw),
      bodyBytes: headBytes,
      bodyFilePath: relativePath,
    ),
    currentJson: _withResponseBodyBytes(
      parseJsonMap(currentRaw),
      bodyBytes: currentBytes,
      bodyFilePath: relativePath,
    ),
  );
}

Future<List<int>?> _readCurrentResponseBodyBytes({
  required GitService git,
  required String workspacePath,
  required String relativePath,
  required List<int>? headBytes,
  required bool isNew,
}) async {
  final bodyFile = File(p.join(workspacePath, relativePath));
  List<int>? workingTreeBytes;
  if (await bodyFile.exists()) {
    workingTreeBytes = await bodyFile.readAsBytes();
  }

  if (!isNew) {
    final indexBytes = await git.showObjectBytes(
      workspacePath,
      ':$relativePath',
    );
    if (indexBytes != null &&
        (workingTreeBytes == null ||
            _bytesEqual(workingTreeBytes, headBytes))) {
      return indexBytes;
    }
  }

  return workingTreeBytes;
}

Map<String, Object?>? _withResponseBodyBytes(
  Map<String, Object?>? json, {
  required List<int>? bodyBytes,
  required String bodyFilePath,
}) {
  if (json == null) {
    if (bodyBytes == null) {
      return null;
    }
    return {
      'headers': {'content-type': _guessResponseBodyContentType(bodyFilePath)},
      'bodyBytes': bodyBytes,
    };
  }
  if (bodyBytes == null) {
    return json;
  }
  return {...json, 'bodyBytes': bodyBytes};
}

String _guessResponseBodyContentType(String bodyFilePath) {
  final extension = p.extension(bodyFilePath).toLowerCase();
  return switch (extension) {
    '.mp3' => 'audio/mpeg',
    '.wav' => 'audio/wav',
    '.ogg' => 'audio/ogg',
    '.mp4' => 'video/mp4',
    '.webm' => 'video/webm',
    '.mov' => 'video/quicktime',
    '.pdf' => 'application/pdf',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    _ => 'application/octet-stream',
  };
}

bool _bytesEqual(List<int>? a, List<int>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Map<String, Object?>? _inlineWorkspaceResponseBodyFile({
  required Map<String, Object?>? json,
  required String workspacePath,
  required String relativePath,
}) {
  if (json == null || p.basename(relativePath) != kWorkspaceResponseFile) {
    return json;
  }
  if (json['bodyBytes'] != null) {
    return json;
  }

  final bodyFileName = json[kWorkspaceResponseBodyFileKey];
  if (bodyFileName is! String || bodyFileName.isEmpty) {
    return json;
  }

  try {
    final bodyFile = File(
      p.join(workspacePath, p.dirname(relativePath), bodyFileName),
    );
    if (!bodyFile.existsSync()) {
      return json;
    }
    return {...json, 'bodyBytes': bodyFile.readAsBytesSync()};
  } catch (_) {
    return json;
  }
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
