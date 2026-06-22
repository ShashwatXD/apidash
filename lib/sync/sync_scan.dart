import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:path/path.dart' as p;

import 'models/sync_models.dart';
import 'storage/sync_storage.dart';

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

bool scanCaseNeedsAdoption(SyncScanCase scanCase) {
  return switch (scanCase) {
    SyncScanCase.sameWorkspace => false,
    SyncScanCase.firstLink || SyncScanCase.differentWorkspace => true,
  };
}

SyncSessionMode sessionModeForScanCase(SyncScanCase scanCase) {
  return switch (scanCase) {
    SyncScanCase.sameWorkspace => SyncSessionMode.incremental,
    SyncScanCase.firstLink || SyncScanCase.differentWorkspace =>
      SyncSessionMode.workspaceReplace,
  };
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
