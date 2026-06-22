enum SyncScanCase { sameWorkspace, firstLink, differentWorkspace }

enum SyncSessionMode {
  incremental,
  firstLinkEmpty,
  firstLinkMerge,
  workspaceReplace,
}

enum SyncFileChangeKind { added, modified, deleted }

enum SyncChangeDirection { incoming, outgoing }

class SyncFileChange {
  const SyncFileChange({
    required this.path,
    required this.kind,
    required this.direction,
  });

  final String path;
  final SyncFileChangeKind kind;
  final SyncChangeDirection direction;

  bool get isIncoming => direction == SyncChangeDirection.incoming;
}

class SyncPeerInfo {
  const SyncPeerInfo({
    required this.workspaceId,
    required this.workspaceName,
    required this.displayName,
  });

  final String workspaceId;
  final String workspaceName;
  final String displayName;
}

class SyncChangeSet {
  const SyncChangeSet({
    this.incoming = const [],
    this.outgoing = const [],
    this.conflicts = const [],
  });

  final List<SyncFileChange> incoming;
  final List<SyncFileChange> outgoing;
  final List<SyncFileChange> conflicts;

  bool get isEmpty =>
      incoming.isEmpty && outgoing.isEmpty && conflicts.isEmpty;
}
