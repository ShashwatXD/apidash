import 'package:apidash/git/models/git_models.dart';

import 'models/sync_models.dart';

GitChangeType syncKindToGitChangeType(SyncFileChangeKind kind) {
  return switch (kind) {
    SyncFileChangeKind.added => GitChangeType.added,
    SyncFileChangeKind.modified => GitChangeType.modified,
    SyncFileChangeKind.deleted => GitChangeType.deleted,
  };
}

GitChange syncFileChangeToGitChange(SyncFileChange change) {
  return GitChange(
    path: change.path,
    type: syncKindToGitChangeType(change.kind),
  );
}

List<GitChange> syncChangesToGitChanges(List<SyncFileChange> changes) {
  return changes.map(syncFileChangeToGitChange).toList();
}

Map<String, SyncFileChange> syncChangesByPath(Iterable<SyncFileChange> changes) {
  return {for (final change in changes) change.path: change};
}
