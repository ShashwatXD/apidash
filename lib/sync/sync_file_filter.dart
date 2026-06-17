import 'package:apidash/consts.dart';

/// Whether a workspace-relative path should be included in LAN sync manifests.
///
/// Mirrors [kGitIgnoreTemplate] in `lib/git/services/git_service.dart`.
bool isSyncablePath(String relativePath) {
  final path = relativePath.replaceAll('\\', '/');
  if (path.isEmpty || path.startsWith('.git/')) {
    return false;
  }
  if (path.startsWith('.apidash/')) {
    return false;
  }
  if (path.startsWith('history/')) {
    return false;
  }
  if (path.endsWith('.tmp')) {
    return false;
  }
  if (path == 'oauth2_credentials.json' || path == 'oauth1_credentials.json') {
    return false;
  }
  if (path.startsWith('$kWorkspaceEnvironmentsDir/') &&
      path.endsWith('.local.json')) {
    return false;
  }
  return path.startsWith('$kWorkspaceCollectionsDir/') ||
      path.startsWith('$kWorkspaceEnvironmentsDir/');
}
