import 'dart:io';

import 'package:apidash/models/models.dart';
import 'package:apidash/services/services.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Ensures mobile always has a valid active workspace before the app boots:
/// rebases saved paths onto the current documents container, drops missing
/// folders, and bootstraps a default workspace on first launch.
Future<SettingsModel?> prepareMobileWorkspaces(SettingsModel? settings) async {
  final base = settings ?? const SettingsModel();
  final parent = await resolveMobileWorkspacesParent();

  final existing = <SavedWorkspaceEntry>[];
  for (final entry in base.savedWorkspaces) {
    final id = p.basename(entry.path);
    if (id.isEmpty) continue;
    final candidate = p.join(parent, id);
    if (Directory(candidate).existsSync()) {
      existing.add(SavedWorkspaceEntry(path: candidate, name: entry.name));
    }
  }

  String? active;
  final currentPath = base.workspaceFolderPath;
  if (currentPath != null && currentPath.isNotEmpty) {
    final candidate = p.join(parent, p.basename(currentPath));
    if (Directory(candidate).existsSync()) {
      active = candidate;
    }
  }
  active ??= existing.isNotEmpty ? existing.first.path : null;

  if (active == null) {
    final id = newWorkspaceId();
    final path = p.join(parent, id);
    final ok = await initWorkspaceStorage(true, path, createIfMissing: true);
    if (ok) {
      await SyncStorage(path).getOrCreateWorkspace(
        name: kDefaultMobileWorkspaceName,
      );
      existing.insert(
        0,
        SavedWorkspaceEntry(path: path, name: kDefaultMobileWorkspaceName),
      );
      active = path;
    } else {
      debugPrint('prepareMobileWorkspaces: bootstrap failed at $path');
      return base;
    }
  }

  final updated = base.copyWith(
    workspaceFolderPath: active,
    savedWorkspaces: existing,
  );
  await setSettingsToSharedPrefs(updated);
  return updated;
}
