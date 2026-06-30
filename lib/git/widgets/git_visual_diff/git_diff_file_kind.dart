import 'package:apidash/consts.dart';

enum GitDiffFileKind {
  request,
  response,
  collection,
  collectionIndex,
  environment,
  environmentIndex,
  unsupported,
}

bool gitDiffSupportsVisual(String path) {
  return detectGitDiffFileKind(path) != GitDiffFileKind.unsupported;
}

GitDiffFileKind detectGitDiffFileKind(String path) {
  final normalized = path.replaceAll('\\', '/');
  final fileName = normalized.split('/').last;

  if (fileName == kWorkspaceRequestFile) {
    return GitDiffFileKind.request;
  }
  if (fileName == kWorkspaceResponseFile) {
    return GitDiffFileKind.response;
  }
  if (fileName == kWorkspaceRequestIndexFile) {
    return GitDiffFileKind.collection;
  }
  if (fileName == kWorkspaceCollectionsIndexFile &&
      normalized == '$kWorkspaceCollectionsDir/$kWorkspaceCollectionsIndexFile') {
    return GitDiffFileKind.collectionIndex;
  }
  if (fileName == kWorkspaceEnvironmentIndexFile &&
      normalized == '$kWorkspaceEnvironmentsDir/$kWorkspaceEnvironmentIndexFile') {
    return GitDiffFileKind.environmentIndex;
  }
  if (normalized.startsWith('$kWorkspaceEnvironmentsDir/') &&
      fileName.endsWith(kJsonFileExtension) &&
      fileName != kWorkspaceEnvironmentIndexFile) {
    return GitDiffFileKind.environment;
  }
  return GitDiffFileKind.unsupported;
}
