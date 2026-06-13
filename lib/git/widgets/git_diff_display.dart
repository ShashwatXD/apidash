import 'dart:convert';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:path/path.dart' as p;

Future<String> resolveGitDiffTitle(
  String workspacePath,
  GitChange change,
) async {
  final fileName = change.path.split('/').last;
  final file = File(p.join(workspacePath, change.path));
  if (!await file.exists()) return fileName;

  try {
    final json = jsonDecode(await file.readAsString());
    if (json is! Map) return fileName;

    if (fileName == kWorkspaceCollectionFile) {
      final name = json[kWorkspaceCollectionNameKey]?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    if (fileName == kWorkspaceRequestFile) {
      final name = json['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
      final http = json['httpRequestModel'];
      if (http is Map) {
        final url = http['url']?.toString().trim();
        if (url != null && url.isNotEmpty) return url;
        final method = http['method']?.toString().trim();
        if (method != null && method.isNotEmpty) {
          return method;
        }
      }
      final parent = p.basename(p.dirname(change.path));
      if (parent.isNotEmpty && parent != kWorkspaceRequestsSubdir) {
        return parent;
      }
    }
    if (change.path.contains('/$kWorkspaceCollectionsDir/') &&
        fileName == kWorkspaceCollectionsIndexFile) {
      return 'Collections index';
    }
    if (_isUnderWorkspaceDir(change.path, kWorkspaceEnvironmentsDir) &&
        fileName == kWorkspaceEnvironmentIndexFile) {
      return 'Environments index';
    }
  } catch (_) {}

  return fileName;
}

bool _isUnderWorkspaceDir(String changePath, String dirName) {
  return changePath == dirName || changePath.startsWith('$dirName/');
}
