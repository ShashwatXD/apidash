import 'package:apidash/consts.dart';

enum GitDiffFileKind {
  request,
  response,
  responseBody,
  collection,
  collectionIndex,
  environment,
  environmentIndex,
  unsupported,
}

bool gitDiffSupportsVisual(String path) {
  return detectGitDiffFileKind(path) != GitDiffFileKind.unsupported;
}

bool gitDiffIsResponseBodyFile(String path) {
  final fileName = path.replaceAll('\\', '/').split('/').last;
  return fileName.startsWith('$kWorkspaceResponseBodyFilePrefix.');
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
  if (gitDiffIsResponseBodyFile(normalized)) {
    return GitDiffFileKind.responseBody;
  }
  if (fileName == kWorkspaceRequestIndexFile) {
    return GitDiffFileKind.collection;
  }
  if (fileName == kWorkspaceCollectionsIndexFile &&
      normalized.endsWith(
        '$kWorkspaceCollectionsDir/$kWorkspaceCollectionsIndexFile',
      )) {
    return GitDiffFileKind.collectionIndex;
  }
  if (fileName == kWorkspaceEnvironmentIndexFile &&
      normalized.endsWith(
        '$kWorkspaceEnvironmentsDir/$kWorkspaceEnvironmentIndexFile',
      )) {
    return GitDiffFileKind.environmentIndex;
  }
  if (normalized.startsWith('$kWorkspaceEnvironmentsDir/') &&
      fileName.endsWith(kJsonFileExtension) &&
      fileName != kWorkspaceEnvironmentIndexFile) {
    return GitDiffFileKind.environment;
  }
  return GitDiffFileKind.unsupported;
}
