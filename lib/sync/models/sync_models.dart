enum SyncScanCase { sameWorkspace, firstLink, differentWorkspace }

enum SyncSessionMode {
  incremental,
  firstLinkEmpty,
  firstLinkMerge,
  workspaceReplace,
}

/// One-way sync: push local changes (send) or pull peer changes (receive).
enum SyncDirectionMode { send, receive }

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
    this.overlappingPaths = const {},
  });

  /// Peer changed since baseline — used in [SyncDirectionMode.receive].
  final List<SyncFileChange> incoming;

  /// Local changed since baseline — used in [SyncDirectionMode.send].
  final List<SyncFileChange> outgoing;

  /// Both sides changed the same path to different content — warn on update.
  final Set<String> overlappingPaths;

  bool get isEmpty => incoming.isEmpty && outgoing.isEmpty;
}
