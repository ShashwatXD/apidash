import 'dart:io';

import 'package:apidash/services/storage/atomic_file_io.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

const kSyncMetaRelativePath = '.apidash/sync/meta.json';
const kSyncPeersRelativeDir = '.apidash/sync/peers';

class SyncWorkspaceMeta {
  const SyncWorkspaceMeta({
    required this.syncWorkspaceId,
    required this.displayName,
  });

  final String syncWorkspaceId;
  final String displayName;

  Map<String, Object?> toJson() => {
        'syncWorkspaceId': syncWorkspaceId,
        'displayName': displayName,
      };

  factory SyncWorkspaceMeta.fromJson(Map<String, Object?> json) {
    return SyncWorkspaceMeta(
      syncWorkspaceId: json['syncWorkspaceId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Workspace',
    );
  }
}

class PeerSyncRecord {
  const PeerSyncRecord({
    required this.peerDeviceId,
    required this.peerDisplayName,
    required this.syncWorkspaceId,
    required this.firstPairedAt,
    required this.lastSyncAt,
    required this.lastMode,
    required this.files,
  });

  final String peerDeviceId;
  final String peerDisplayName;
  final String syncWorkspaceId;
  final String firstPairedAt;
  final String lastSyncAt;
  final String lastMode;
  final Map<String, String> files;

  Map<String, Object?> toJson() => {
        'peerDeviceId': peerDeviceId,
        'peerDisplayName': peerDisplayName,
        'syncWorkspaceId': syncWorkspaceId,
        'firstPairedAt': firstPairedAt,
        'lastSyncAt': lastSyncAt,
        'lastMode': lastMode,
        'files': files,
      };

  factory PeerSyncRecord.fromJson(Map<String, Object?> json) {
    final rawFiles = json['files'];
    final files = <String, String>{};
    if (rawFiles is Map) {
      for (final entry in rawFiles.entries) {
        files['${entry.key}'] = '${entry.value}';
      }
    }
    return PeerSyncRecord(
      peerDeviceId: json['peerDeviceId'] as String? ?? '',
      peerDisplayName: json['peerDisplayName'] as String? ?? '',
      syncWorkspaceId: json['syncWorkspaceId'] as String? ?? '',
      firstPairedAt: json['firstPairedAt'] as String? ?? '',
      lastSyncAt: json['lastSyncAt'] as String? ?? '',
      lastMode: json['lastMode'] as String? ?? 'sync',
      files: files,
    );
  }
}

class PeerSyncStore {
  PeerSyncStore(this.workspaceRoot);

  final String workspaceRoot;

  String get _metaPath => p.join(workspaceRoot, kSyncMetaRelativePath);

  String _peerPath(String peerDeviceId) =>
      p.join(workspaceRoot, kSyncPeersRelativeDir, '$peerDeviceId.json');

  Future<SyncWorkspaceMeta> getOrCreateMeta({String? displayName}) async {
    final existing = await readJsonFile(_metaPath);
    if (existing != null) {
      return SyncWorkspaceMeta.fromJson(existing);
    }

    final meta = SyncWorkspaceMeta(
      syncWorkspaceId: 'ws-${const Uuid().v4()}',
      displayName: displayName ?? p.basename(workspaceRoot),
    );
    await writeJsonAtomic(_metaPath, meta.toJson());
    return meta;
  }

  Future<PeerSyncRecord?> getPeer(String peerDeviceId) async {
    final json = await readJsonFile(_peerPath(peerDeviceId));
    if (json == null) return null;
    return PeerSyncRecord.fromJson(json);
  }

  Future<bool> hasPaired(String peerDeviceId, String syncWorkspaceId) async {
    final peer = await getPeer(peerDeviceId);
    return peer != null && peer.syncWorkspaceId == syncWorkspaceId;
  }

  Future<void> savePeer(PeerSyncRecord record) async {
    final peersDir = Directory(p.join(workspaceRoot, kSyncPeersRelativeDir));
    if (!await peersDir.exists()) {
      await peersDir.create(recursive: true);
    }
    await writeJsonAtomic(_peerPath(record.peerDeviceId), record.toJson());
  }

  Future<List<PeerSyncRecord>> listPeers() async {
    final peersDir = Directory(p.join(workspaceRoot, kSyncPeersRelativeDir));
    if (!await peersDir.exists()) {
      return const [];
    }
    final records = <PeerSyncRecord>[];
    await for (final entity in peersDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final json = await readJsonFile(entity.path);
      if (json != null) {
        records.add(PeerSyncRecord.fromJson(json));
      }
    }
    return records;
  }

  Future<PeerSyncRecord?> mostRecentPeer() async {
    final peers = await listPeers();
    if (peers.isEmpty) return null;
    peers.sort((a, b) => b.lastSyncAt.compareTo(a.lastSyncAt));
    return peers.first;
  }
}
