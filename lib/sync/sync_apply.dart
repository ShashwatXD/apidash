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

/// Applies accepted incoming changes to disk, sends outgoing files to the peer,
/// and persists the updated sync baseline.
Future<SyncApplyResult> applySyncSession({
  required String workspaceRoot,
  required PeerSyncStore peerStore,
  required SyncWorkspaceMeta workspaceMeta,
  required SyncPeerInfo peer,
  required SyncChangeSet changeSet,
  required Set<String> acceptedPaths,
  required SyncFileTransfer transfer,
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
      throw StateError('Phone did not send ${change.path}');
    }
    await writeSyncableWorkspaceFile(workspaceRoot, change.path, content);
    appliedIncoming++;
  }

  var sentOutgoing = 0;
  for (final change in changeSet.outgoing) {
    if (change.kind == SyncFileChangeKind.deleted) {
      await transfer.sendDeletedFile(change.path);
    } else {
      final content = await readSyncableWorkspaceFile(workspaceRoot, change.path);
      if (content == null) {
        throw StateError('Local file missing: ${change.path}');
      }
      await transfer.sendLocalFile(change.path, content);
    }
    sentOutgoing++;
  }

  final newBaseline = await buildSyncManifest(workspaceRoot);
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
  await transfer.sendApplyComplete(newBaseline);

  return SyncApplyResult(
    appliedIncoming: appliedIncoming,
    sentOutgoing: sentOutgoing,
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
