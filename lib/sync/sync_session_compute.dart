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

List<SyncFileChange> changesForDirection(
  SyncChangeSet changeSet,
  SyncDirectionMode mode,
) {
  return switch (mode) {
    SyncDirectionMode.send => changeSet.outgoing,
    SyncDirectionMode.receive => changeSet.incoming,
  };
}

SyncDirectionMode defaultDirectionMode(SyncChangeSet changeSet) {
  if (changeSet.outgoing.isNotEmpty) return SyncDirectionMode.send;
  if (changeSet.incoming.isNotEmpty) return SyncDirectionMode.receive;
  return SyncDirectionMode.send;
}

bool directionHasWork(SyncChangeSet changeSet, SyncDirectionMode mode) {
  return changesForDirection(changeSet, mode).isNotEmpty;
}

Set<String> overlappingForDirection(
  SyncChangeSet changeSet,
  SyncDirectionMode mode,
) {
  final activePaths =
      changesForDirection(changeSet, mode).map((c) => c.path).toSet();
  return changeSet.overlappingPaths.intersection(activePaths);
}

String? overlapWarningMessage({
  required SyncDirectionMode mode,
  required Set<String> overlapping,
  required bool isHost,
}) {
  if (overlapping.isEmpty) return null;
  final count = overlapping.length;
  final files = count == 1 ? 'file' : 'files';
  return switch (mode) {
    SyncDirectionMode.send when isHost =>
      'Phone also edited $count $files. Your version will replace theirs.',
    SyncDirectionMode.send =>
      'Computer also edited $count $files. Your version will replace theirs.',
    SyncDirectionMode.receive when isHost =>
      'You also edited $count $files. Phone\'s version will replace yours.',
    SyncDirectionMode.receive =>
      'You also edited $count $files. Computer\'s version will replace yours.',
  };
}

String directionListTitle({
  required SyncDirectionMode mode,
  required bool isHost,
}) {
  return switch (mode) {
    SyncDirectionMode.send when isHost => kLabelSyncSendingToPhone,
    SyncDirectionMode.send => kLabelSyncSendingToComputer,
    SyncDirectionMode.receive when isHost => kLabelSyncReceivingFromPhone,
    SyncDirectionMode.receive => kLabelSyncReceivingFromComputer,
  };
}

String updateButtonLabel({
  required SyncDirectionMode mode,
  required bool isHost,
  required int count,
  required bool updating,
}) {
  if (updating) return kLabelSyncUpdating;
  if (count == 0) return kLabelSyncAlreadyInSync;
  return switch (mode) {
    SyncDirectionMode.send when isHost => '$kLabelSyncUpdatePhone ($count)',
    SyncDirectionMode.send => '$kLabelSyncUpdateComputer ($count)',
    SyncDirectionMode.receive when isHost =>
      '$kLabelSyncUpdateFromPhone ($count)',
    SyncDirectionMode.receive => '$kLabelSyncUpdateFromComputer ($count)',
  };
}

String directionSummary({
  required SyncChangeSet changeSet,
  required bool isHost,
}) {
  final sendCount = changeSet.outgoing.length;
  final receiveCount = changeSet.incoming.length;
  if (sendCount == 0 && receiveCount == 0) return kLabelSyncAlreadyInSync;
  final youLabel = isHost ? 'Computer' : 'Phone';
  final peerLabel = isHost ? 'Phone' : 'Computer';
  return '$youLabel: $sendCount to send · $peerLabel: $receiveCount to send';
}

bool peersPairedBefore({
  required bool localHadBaseline,
  required bool peerHadBaseline,
}) {
  return localHadBaseline && peerHadBaseline;
}

String applyButtonLabel({
  required SyncSessionMode mode,
  required bool hasWork,
}) {
  if (!hasWork) return kLabelSyncAlreadyInSync;
  return switch (mode) {
    SyncSessionMode.workspaceReplace => kLabelSyncSwitchAndSync,
    SyncSessionMode.incremental => kLabelSyncUpdate,
    _ => kLabelSyncUpdate,
  };
}
