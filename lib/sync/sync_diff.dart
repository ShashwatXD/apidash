import 'models/sync_models.dart';

/// Compares [baseline] (last agreed sync) with [local] and [peer] manifests.
SyncChangeSet computeSyncChangeSet({
  required Map<String, String> baseline,
  required Map<String, String> local,
  required Map<String, String> peer,
  bool peerHasBaseline = true,
}) {
  final incoming = <SyncFileChange>[];
  final outgoing = <SyncFileChange>[];
  final conflicts = <SyncFileChange>[];

  final paths = <String>{
    ...baseline.keys,
    ...local.keys,
    ...peer.keys,
  };

  for (final path in paths) {
    final baseHash = baseline[path];
    final localHash = local[path];
    final peerHash = peer[path];

    // Peer never synced: missing paths are not peer edits — only local vs baseline.
    if (!peerHasBaseline && peerHash == null) {
      final hostChanged = localHash != baseHash;
      if (!hostChanged) {
        if (baseHash != null) {
          outgoing.add(
            SyncFileChange(
              path: path,
              kind: _kindForHostChange(baseHash, localHash),
              direction: SyncChangeDirection.outgoing,
            ),
          );
        }
      } else {
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

    final hostChanged = localHash != baseHash;
    final peerChanged = peerHash != baseHash;

    if (!hostChanged && !peerChanged) continue;

    if (hostChanged && peerChanged) {
      conflicts.add(
        SyncFileChange(
          path: path,
          kind: _kindForPath(baseHash, localHash, peerHash),
          direction: SyncChangeDirection.incoming,
        ),
      );
      continue;
    }

    if (peerChanged) {
      incoming.add(
        SyncFileChange(
          path: path,
          kind: _kindForPeerChange(baseHash, peerHash),
          direction: SyncChangeDirection.incoming,
        ),
      );
      continue;
    }

    outgoing.add(
      SyncFileChange(
        path: path,
        kind: _kindForHostChange(baseHash, localHash),
        direction: SyncChangeDirection.outgoing,
      ),
    );
  }

  return SyncChangeSet(
    incoming: incoming,
    outgoing: outgoing,
    conflicts: conflicts,
  );
}

SyncFileChangeKind _kindForPath(
  String? baseline,
  String? local,
  String? peer,
) {
  if (baseline == null) return SyncFileChangeKind.added;
  if (local == null || peer == null) return SyncFileChangeKind.deleted;
  return SyncFileChangeKind.modified;
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
