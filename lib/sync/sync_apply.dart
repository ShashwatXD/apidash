import 'models/sync_models.dart';
import 'storage/sync_storage.dart';
import 'sync_diff.dart';
import 'sync_manifest_builder.dart';
import 'sync_workspace_io.dart';
import 'transport/sync_file_transfer.dart';

class SyncApplyResult {
  const SyncApplyResult({
    required this.appliedIncoming,
    required this.sentOutgoing,
    required this.newBaseline,
  });

  final int appliedIncoming;
  final int sentOutgoing;
  final Map<String, String> newBaseline;
}

Future<SyncApplyResult> applySyncSession({
  required String workspaceRoot,
  required SyncStorage storage,
  required SyncPeerInfo peer,
  required SyncChangeSet changeSet,
  required Set<String> acceptedPaths,
  required SyncFileTransfer transfer,
  required Map<String, String> peerManifest,
}) async {
  final acceptedIncoming = [
    ...changeSet.incoming,
    ...changeSet.conflicts,
  ].where((change) => acceptedPaths.contains(change.path)).toList();

  var appliedIncoming = 0;
  for (final change in acceptedIncoming) {
    if (change.kind == SyncFileChangeKind.deleted) {
      await deleteSyncableWorkspaceFile(workspaceRoot, change.path);
      appliedIncoming++;
      continue;
    }

    final content = await transfer.fetchPeerFile(change.path);
    if (content == null) {
      throw StateError('Peer did not send ${change.path}');
    }
    await writeSyncableWorkspaceFile(workspaceRoot, change.path, content);
    appliedIncoming++;
  }

  return _finalizeApply(
    workspaceRoot: workspaceRoot,
    storage: storage,
    peer: peer,
    transfer: transfer,
    peerManifest: peerManifest,
    appliedIncoming: appliedIncoming,
  );
}

Future<SyncApplyResult> applyReplaceFromPeer({
  required String workspaceRoot,
  required SyncStorage storage,
  required SyncPeerInfo peer,
  required SyncFileTransfer transfer,
  required Map<String, String> peerManifest,
}) async {
  var appliedIncoming = 0;
  for (final path in peerManifest.keys) {
    final content = await transfer.fetchPeerFile(path);
    if (content == null) continue;
    await writeSyncableWorkspaceFile(workspaceRoot, path, content);
    appliedIncoming++;
  }

  final localManifest = await buildSyncManifest(workspaceRoot);
  for (final path in localManifest.keys) {
    if (!peerManifest.containsKey(path)) {
      await deleteSyncableWorkspaceFile(workspaceRoot, path);
    }
  }

  return _finalizeApply(
    workspaceRoot: workspaceRoot,
    storage: storage,
    peer: peer,
    transfer: transfer,
    peerManifest: peerManifest,
    appliedIncoming: appliedIncoming,
  );
}

Future<SyncApplyResult> _finalizeApply({
  required String workspaceRoot,
  required SyncStorage storage,
  required SyncPeerInfo peer,
  required SyncFileTransfer transfer,
  required Map<String, String> peerManifest,
  required int appliedIncoming,
}) async {
  final newBaseline = await buildSyncManifest(workspaceRoot);

  final writes = <String, String>{};
  for (final entry in newBaseline.entries) {
    if (peerManifest[entry.key] == entry.value) continue;
    final content = await readSyncableWorkspaceFile(workspaceRoot, entry.key);
    if (content != null) writes[entry.key] = content;
  }
  final deletes = <String>[
    for (final path in peerManifest.keys)
      if (!newBaseline.containsKey(path)) path,
  ];

  final now = DateTime.now().toUtc().toIso8601String();
  await storage.saveSyncState(
    SyncState(
      lastSyncAt: now,
      peerDisplayName: peer.displayName,
      baseline: newBaseline,
    ),
  );
  await transfer.sendApplyComplete(newBaseline, writes: writes, deletes: deletes);

  return SyncApplyResult(
    appliedIncoming: appliedIncoming,
    sentOutgoing: writes.length + deletes.length,
    newBaseline: newBaseline,
  );
}

Future<int> countUnsyncedOutgoingChanges(String workspaceRoot) async {
  final local = await buildSyncManifest(workspaceRoot);
  final storage = SyncStorage(workspaceRoot);
  final state = await storage.readSyncState();
  if (state == null || !state.hasBaseline) return 0;
  final changeSet = computeSyncChangeSet(
    baseline: state.baseline,
    local: local,
    peer: state.baseline,
  );
  return changeSet.outgoing.length;
}
