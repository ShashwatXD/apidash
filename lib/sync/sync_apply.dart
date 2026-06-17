import 'models/sync_models.dart';
import 'storage/peer_sync_store.dart';
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

/// Applies the reviewed result so both devices converge from a single Apply.
Future<SyncApplyResult> applySyncSession({
  required String workspaceRoot,
  required PeerSyncStore peerStore,
  required SyncWorkspaceMeta workspaceMeta,
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
  final existing = await peerStore.getPeer(peer.deviceId);
  final record = PeerSyncRecord(
    peerDeviceId: peer.deviceId,
    peerDisplayName: peer.displayName,
    syncWorkspaceId: workspaceMeta.syncWorkspaceId,
    firstPairedAt: existing?.firstPairedAt ?? now,
    lastSyncAt: now,
    lastMode: existing == null ? 'transfer' : 'sync',
    files: newBaseline,
  );
  await peerStore.savePeer(record);
  await transfer.sendApplyComplete(newBaseline, writes: writes, deletes: deletes);

  return SyncApplyResult(
    appliedIncoming: appliedIncoming,
    sentOutgoing: writes.length + deletes.length,
    newBaseline: newBaseline,
  );
}

Future<int> countUnsyncedOutgoingChanges(String workspaceRoot) async {
  final local = await buildSyncManifest(workspaceRoot);
  final peerStore = PeerSyncStore(workspaceRoot);
  final peer = await peerStore.mostRecentPeer();
  if (peer == null) return 0;
  final changeSet = computeSyncChangeSet(
    baseline: peer.files,
    local: local,
    peer: peer.files,
  );
  return changeSet.outgoing.length;
}
