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

/// Push local [outgoing] changes to the peer. Local disk is unchanged.
Future<SyncApplyResult> applySend({
  required String workspaceRoot,
  required SyncStorage storage,
  required SyncPeerInfo peer,
  required List<SyncFileChange> outgoing,
  required SyncFileTransfer transfer,
  required Map<String, String> peerManifest,
}) async {
  final writes = <String, String>{};
  final deletes = <String>[];

  for (final change in outgoing) {
    if (change.kind == SyncFileChangeKind.deleted) {
      deletes.add(change.path);
      continue;
    }
    final content = await readSyncableWorkspaceFile(workspaceRoot, change.path);
    if (content != null) writes[change.path] = content;
  }

  final state = await storage.readSyncState();
  final oldBaseline = state?.baseline ?? const <String, String>{};
  final localManifest = await buildSyncManifest(workspaceRoot);
  final paths = outgoing.map((c) => c.path);
  final newBaseline = _mergeBaseline(oldBaseline, localManifest, paths);

  return _persistAndNotifyPeer(
    storage: storage,
    peer: peer,
    transfer: transfer,
    newBaseline: newBaseline,
    writes: writes,
    deletes: deletes,
    appliedIncoming: 0,
    sentOutgoing: writes.length + deletes.length,
  );
}

/// Pull [incoming] changes from the peer. Peer disk is unchanged.
Future<SyncApplyResult> applyReceive({
  required String workspaceRoot,
  required SyncStorage storage,
  required SyncPeerInfo peer,
  required List<SyncFileChange> incoming,
  required SyncFileTransfer transfer,
  required Map<String, String> peerManifest,
}) async {
  var appliedIncoming = 0;
  for (final change in incoming) {
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

  final state = await storage.readSyncState();
  final oldBaseline = state?.baseline ?? const <String, String>{};
  final paths = incoming.map((c) => c.path);
  final newBaseline = _mergeBaseline(oldBaseline, peerManifest, paths);

  return _persistAndNotifyPeer(
    storage: storage,
    peer: peer,
    transfer: transfer,
    newBaseline: newBaseline,
    appliedIncoming: appliedIncoming,
    sentOutgoing: 0,
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

  final newBaseline = await buildSyncManifest(workspaceRoot);
  return _persistAndNotifyPeer(
    storage: storage,
    peer: peer,
    transfer: transfer,
    newBaseline: newBaseline,
    appliedIncoming: appliedIncoming,
    sentOutgoing: 0,
  );
}

Map<String, String> _mergeBaseline(
  Map<String, String> oldBaseline,
  Map<String, String> manifest,
  Iterable<String> paths,
) {
  final merged = Map<String, String>.from(oldBaseline);
  for (final path in paths) {
    final hash = manifest[path];
    if (hash == null) {
      merged.remove(path);
    } else {
      merged[path] = hash;
    }
  }
  return merged;
}

Future<SyncApplyResult> _persistAndNotifyPeer({
  required SyncStorage storage,
  required SyncPeerInfo peer,
  required SyncFileTransfer transfer,
  required Map<String, String> newBaseline,
  Map<String, String> writes = const {},
  List<String> deletes = const [],
  required int appliedIncoming,
  required int sentOutgoing,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await storage.saveSyncState(
    SyncState(
      lastSyncAt: now,
      peerDisplayName: peer.displayName,
      baseline: newBaseline,
    ),
  );
  await transfer.sendApplyComplete(
    newBaseline,
    writes: writes,
    deletes: deletes,
  );

  return SyncApplyResult(
    appliedIncoming: appliedIncoming,
    sentOutgoing: sentOutgoing,
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
