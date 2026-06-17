enum SyncFileChangeKind { added, modified, deleted }

enum SyncChangeDirection { incoming, outgoing }

class SyncFileChange {
  const SyncFileChange({
    required this.path,
    required this.kind,
    required this.direction,
    this.peerContent,
    this.localContent,
  });

  final String path;
  final SyncFileChangeKind kind;
  final SyncChangeDirection direction;

  /// Peer device content (phone when hosting on desktop).
  final String? peerContent;

  /// This device's content (desktop when hosting).
  final String? localContent;

  bool get isIncoming => direction == SyncChangeDirection.incoming;

  SyncFileChange copyWith({
    String? localContent,
    String? peerContent,
  }) {
    return SyncFileChange(
      path: path,
      kind: kind,
      direction: direction,
      localContent: localContent ?? this.localContent,
      peerContent: peerContent ?? this.peerContent,
    );
  }
}

class SyncPeerInfo {
  const SyncPeerInfo({
    required this.deviceId,
    required this.displayName,
    required this.syncWorkspaceId,
  });

  final String deviceId;
  final String displayName;
  final String syncWorkspaceId;
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

class SyncSessionPreview {
  const SyncSessionPreview({
    required this.peer,
    required this.changeSet,
    this.isConnected = false,
    this.wasPairedBefore = false,
  });

  final SyncPeerInfo peer;
  final SyncChangeSet changeSet;
  final bool isConnected;
  final bool wasPairedBefore;
}
