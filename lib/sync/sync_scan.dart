import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:path/path.dart' as p;

import 'models/sync_models.dart';
import 'storage/sync_storage.dart';
import 'sync_manifest_builder.dart';

SyncScanCase resolveScanCase({
  required String? localWorkspaceId,
  required String qrWorkspaceId,
}) {
  if (localWorkspaceId == null || localWorkspaceId.isEmpty) {
    return SyncScanCase.firstLink;
  }
  if (localWorkspaceId == qrWorkspaceId) {
    return SyncScanCase.sameWorkspace;
  }
  return SyncScanCase.differentWorkspace;
}

SyncSessionMode resolveSessionMode({
  required SyncScanCase scanCase,
  required bool phoneHasLocalData,
  bool useDesktopOnly = false,
}) {
  return switch (scanCase) {
    SyncScanCase.sameWorkspace => SyncSessionMode.incremental,
    SyncScanCase.differentWorkspace => SyncSessionMode.workspaceReplace,
    SyncScanCase.firstLink => phoneHasLocalData
        ? (useDesktopOnly
            ? SyncSessionMode.workspaceReplace
            : SyncSessionMode.firstLinkMerge)
        : SyncSessionMode.firstLinkEmpty,
  };
}

Future<bool> phoneHasLocalSyncableData(String workspaceRoot) async {
  final manifest = await buildSyncManifest(workspaceRoot);
  return manifest.isNotEmpty;
}

Future<void> wipePhoneWorkspaceData(String workspaceRoot) async {
  for (final dirName in [kWorkspaceCollectionsDir, kWorkspaceEnvironmentsDir]) {
    final dir = Directory(p.join(workspaceRoot, dirName));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
  }
  await SyncStorage(workspaceRoot).clearSyncState();
}

Future<void> adoptWorkspaceIdentity(
  String workspaceRoot, {
  required WorkspaceIdentity identity,
}) async {
  await SyncStorage(workspaceRoot).writeWorkspace(identity);
}
