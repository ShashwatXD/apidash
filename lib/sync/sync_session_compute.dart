import 'models/sync_models.dart';
import 'sync_diff.dart';
import 'consts.dart';

SyncChangeSet computeSessionChangeSet({
  required Map<String, String> baseline,
  required Map<String, String> local,
  required Map<String, String> peer,
  required bool peerHasBaseline,
}) {
  return computeSyncChangeSet(
    baseline: baseline,
    local: local,
    peer: peer,
    peerHasBaseline: peerHasBaseline,
  );
}

/// Incoming from peer + same-file conflicts — one review list, checkbox = use peer.
List<SyncFileChange> syncReviewableFromPeer(SyncChangeSet changeSet) {
  return [...changeSet.incoming, ...changeSet.conflicts];
}

Set<String> defaultAcceptedPaths(SyncChangeSet changeSet) {
  return syncReviewableFromPeer(changeSet).map((c) => c.path).toSet();
}

bool sessionHasWork(SyncChangeSet changeSet, Set<String> acceptedPaths) {
  return acceptedPaths.isNotEmpty || changeSet.outgoing.isNotEmpty;
}

String applyButtonLabel({
  required SyncSessionMode mode,
  required bool hasWork,
}) {
  if (!hasWork) return kLabelSyncAlreadyInSync;
  return switch (mode) {
    SyncSessionMode.workspaceReplace => kLabelSyncSwitchAndSync,
    SyncSessionMode.incremental => kLabelSyncApplyAndSync,
    _ => kLabelSyncApplyAndSync,
  };
}
