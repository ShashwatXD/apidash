import 'dart:io';

import 'package:apidash/providers/providers.dart';
import 'package:apidash/services/services.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

Future<String?> createMobileWorkspace(
  WidgetRef ref, {
  String? id,
  required String name,
}) async {
  final workspaceId = (id != null && id.isNotEmpty) ? id : newWorkspaceId();
  final path = await resolveMobileWorkspacePath(workspaceId);

  final ok = await activateWorkspace(ref, path, createIfMissing: true);
  if (!ok) {
    return null;
  }

  await SyncStorage(path).writeWorkspace(
    WorkspaceIdentity(id: workspaceId, name: name),
  );
  await ref.read(settingsProvider.notifier).rememberWorkspace(
        path: path,
        name: name,
      );
  return workspaceId;
}

Future<void> renameMobileWorkspace(
  WidgetRef ref, {
  required String path,
  required String name,
}) async {
  await ref.read(settingsProvider.notifier).renameWorkspace(
        path: path,
        name: name,
      );
  try {
    final storage = SyncStorage(path);
    final existing = await storage.readWorkspace();
    if (existing != null) {
      await storage.writeWorkspace(
        WorkspaceIdentity(id: existing.id, name: name),
      );
    }
  } catch (_) {}
}

/// Deletes a workspace folder. If it was active, switches to another workspace;
/// if it was the last one, bootstraps a fresh default workspace.
Future<bool> deleteMobileWorkspace(WidgetRef ref, String path) async {
  final normalized = p.normalize(path);
  final settingsNotifier = ref.read(settingsProvider.notifier);
  final settings = ref.read(settingsProvider);
  final wasActive =
      p.normalize(settings.workspaceFolderPath ?? '') == normalized;

  final remaining = settings.savedWorkspaces
      .where((e) => p.normalize(e.path) != normalized)
      .toList();

  try {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (e) {
    return false;
  }

  await settingsNotifier.forgetWorkspace(path);

  if (!wasActive) {
    return true;
  }

  if (remaining.isNotEmpty) {
    return activateWorkspace(ref, remaining.first.path, createIfMissing: false);
  }

  final id = await createMobileWorkspace(
    ref,
    name: kDefaultMobileWorkspaceName,
  );
  return id != null;
}
