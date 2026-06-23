import 'models/sync_models.dart';

/// Compares [baseline] (last agreed sync) with [local] and [peer] manifests.
///
/// [incoming] = peer changed since baseline (receive list).
/// [outgoing] = local changed since baseline (send list).
/// When both changed the same path it appears in both lists; divergent
/// content is tracked in [overlappingPaths] for overwrite warnings.
SyncChangeSet computeSyncChangeSet({
  required Map<String, String> baseline,
  required Map<String, String> local,
  required Map<String, String> peer,
  bool peerHasBaseline = true,
}) {
  final incoming = <SyncFileChange>[];
  final outgoing = <SyncFileChange>[];
  final overlappingPaths = <String>{};

  final paths = <String>{
    ...baseline.keys,
    ...local.keys,
    ...peer.keys,
  };

  for (final path in paths) {
    final baseHash = baseline[path];
    final localHash = local[path];
    final peerHash = peer[path];

    if (!peerHasBaseline && peerHash == null) {
      if (localHash != baseHash) {
        outgoing.add(
          SyncFileChange(
            path: path,
            kind: _kindForHostChange(baseHash, localHash),
            direction: SyncChangeDirection.outgoing,
          ),
        );
      }
      continue;
    }

    final localChanged = localHash != baseHash;
    final peerChanged = peerHash != baseHash;

    if (!localChanged && !peerChanged) continue;

    if (localChanged && peerChanged && localHash != peerHash) {
      overlappingPaths.add(path);
    }

    if (peerChanged) {
      incoming.add(
        SyncFileChange(
          path: path,
          kind: _kindForPeerChange(baseHash, peerHash),
          direction: SyncChangeDirection.incoming,
        ),
      );
    }

    if (localChanged) {
      outgoing.add(
        SyncFileChange(
          path: path,
          kind: _kindForHostChange(baseHash, localHash),
          direction: SyncChangeDirection.outgoing,
        ),
      );
    }
  }

  return SyncChangeSet(
    incoming: incoming,
    outgoing: outgoing,
    overlappingPaths: overlappingPaths,
  );
}

SyncFileChangeKind _kindForPeerChange(String? baseline, String? peer) {
  if (baseline == null) return SyncFileChangeKind.added;
  if (peer == null) return SyncFileChangeKind.deleted;
  return SyncFileChangeKind.modified;
}

SyncFileChangeKind _kindForHostChange(String? baseline, String? local) {
  if (baseline == null) return SyncFileChangeKind.added;
  if (local == null) return SyncFileChangeKind.deleted;
  return SyncFileChangeKind.modified;
}

/// Paths that differ between [local] and [peer] with no baseline history.
SyncChangeSet computeTransferChangeSet({
  required Map<String, String> local,
  required Map<String, String> peer,
}) {
  return computeSyncChangeSet(
    baseline: const {},
    local: local,
    peer: peer,
    peerHasBaseline: false,
  );
}
