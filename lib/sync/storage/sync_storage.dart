import 'dart:io';

import 'package:apidash/services/storage/atomic_file_io.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../consts.dart';

String newWorkspaceId() => 'ws-${const Uuid().v4()}';

class WorkspaceIdentity {
  const WorkspaceIdentity({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory WorkspaceIdentity.fromJson(Map<String, Object?> json) {
    return WorkspaceIdentity(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Workspace',
    );
  }
}

class SyncState {
  const SyncState({
    this.lastSyncAt,
    this.peerDisplayName,
    this.baseline = const {},
  });

  final String? lastSyncAt;
  final String? peerDisplayName;
  final Map<String, String> baseline;

  bool get hasBaseline => baseline.isNotEmpty;

  Map<String, Object?> toJson() => {
        'lastSyncAt': lastSyncAt,
        'peerDisplayName': peerDisplayName,
        'baseline': baseline,
      };

  factory SyncState.fromJson(Map<String, Object?> json) {
    final rawBaseline = json['baseline'];
    final baseline = <String, String>{};
    if (rawBaseline is Map) {
      for (final entry in rawBaseline.entries) {
        baseline['${entry.key}'] = '${entry.value}';
      }
    }
    return SyncState(
      lastSyncAt: json['lastSyncAt'] as String?,
      peerDisplayName: json['peerDisplayName'] as String?,
      baseline: baseline,
    );
  }
}

class SyncStorage {
  SyncStorage(this.workspaceRoot);

  final String workspaceRoot;

  String get _workspacePath => p.join(workspaceRoot, kWorkspaceIdentityRelativePath);
  String get _syncPath => p.join(workspaceRoot, kSyncStateRelativePath);

  Future<WorkspaceIdentity?> readWorkspace() async {
    final json = await readJsonFile(_workspacePath);
    if (json == null) return null;
    return WorkspaceIdentity.fromJson(json);
  }

  Future<WorkspaceIdentity> getOrCreateWorkspace({String? name}) async {
    final existing = await readWorkspace();
    if (existing != null && existing.id.isNotEmpty) return existing;

    final identity = WorkspaceIdentity(
      id: newWorkspaceId(),
      name: name ?? p.basename(workspaceRoot),
    );
    await writeWorkspace(identity);
    return identity;
  }

  Future<void> writeWorkspace(WorkspaceIdentity identity) async {
    await _ensureApidashDir();
    await writeJsonAtomic(_workspacePath, identity.toJson());
  }

  Future<SyncState?> readSyncState() async {
    final json = await readJsonFile(_syncPath);
    if (json == null) return null;
    return SyncState.fromJson(json);
  }

  Future<void> saveSyncState(SyncState state) async {
    await _ensureApidashDir();
    await writeJsonAtomic(_syncPath, state.toJson());
  }

  Future<void> clearSyncState() async {
    final file = File(_syncPath);
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteApidashDir() async {
    final dir = Directory(p.join(workspaceRoot, kSyncApidashDir));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<bool> hasSyncedBefore() async {
    final state = await readSyncState();
    return state != null && state.hasBaseline;
  }

  Future<void> _ensureApidashDir() async {
    final dir = Directory(p.join(workspaceRoot, kSyncApidashDir));
    if (!await dir.exists()) await dir.create(recursive: true);
  }
}
