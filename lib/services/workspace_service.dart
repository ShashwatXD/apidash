import 'dart:convert';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/git/providers/git_status_provider.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

enum WorkspaceValidationStatus {
  valid,
  missingFolder,
  notApidashWorkspace,
  invalidFormat,
  unreadable,
}

class WorkspaceValidationResult {
  const WorkspaceValidationResult({
    required this.status,
    this.collectionsIndexPath,
    this.environmentsIndexPath,
  });

  final WorkspaceValidationStatus status;
  final String? collectionsIndexPath;
  final String? environmentsIndexPath;

  bool get isValid => status == WorkspaceValidationStatus.valid;
}

Future<WorkspaceValidationResult> validateLocalApidashWorkspace(
  String path,
) async {
  final normalized = p.normalize(path);
  final root = Directory(normalized);
  if (!await root.exists()) {
    return const WorkspaceValidationResult(
      status: WorkspaceValidationStatus.missingFolder,
    );
  }

  final collectionsIndexPath = p.join(
    normalized,
    kWorkspaceCollectionsDir,
    kWorkspaceCollectionsIndexFile,
  );
  final environmentsIndexPath = p.join(
    normalized,
    kWorkspaceEnvironmentsDir,
    kWorkspaceEnvironmentIndexFile,
  );

  final collectionsFile = File(collectionsIndexPath);
  final environmentsFile = File(environmentsIndexPath);
  final hasCollections = await collectionsFile.exists();
  final hasEnvironments = await environmentsFile.exists();

  if (!hasCollections || !hasEnvironments) {
    return WorkspaceValidationResult(
      status: WorkspaceValidationStatus.notApidashWorkspace,
      collectionsIndexPath: collectionsIndexPath,
      environmentsIndexPath: environmentsIndexPath,
    );
  }

  try {
    final collectionsJson = await collectionsFile.readAsString();
    final environmentsJson = await environmentsFile.readAsString();
    final valid = parseApidashWorkspaceIndices(
      collectionsIndexJson: collectionsJson,
      environmentsIndexJson: environmentsJson,
    );
    if (!valid) {
      return WorkspaceValidationResult(
        status: WorkspaceValidationStatus.invalidFormat,
        collectionsIndexPath: collectionsIndexPath,
        environmentsIndexPath: environmentsIndexPath,
      );
    }
    return WorkspaceValidationResult(
      status: WorkspaceValidationStatus.valid,
      collectionsIndexPath: collectionsIndexPath,
      environmentsIndexPath: environmentsIndexPath,
    );
  } catch (_) {
    return WorkspaceValidationResult(
      status: WorkspaceValidationStatus.unreadable,
      collectionsIndexPath: collectionsIndexPath,
      environmentsIndexPath: environmentsIndexPath,
    );
  }
}

bool isValidWorkspaceFolderName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == '.' || trimmed == '..') return false;
  if (trimmed.contains('/') || trimmed.contains('\\')) return false;
  return true;
}

bool parseApidashWorkspaceIndices({
  required String collectionsIndexJson,
  required String environmentsIndexJson,
}) {
  try {
    final collections = jsonDecode(collectionsIndexJson);
    final environments = jsonDecode(environmentsIndexJson);
    if (collections is! Map || environments is! Map) return false;
    if (collections[kWorkspaceCollectionsIndexKey] is! List) return false;
    if (environments[kWorkspaceEnvironmentIdsKey] is! List) return false;
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> activateWorkspace(
  WidgetRef ref,
  String path, {
  bool createIfMissing = true,
}) async {
  final opened = await initWorkspaceStorage(
    kIsDesktop,
    path,
    createIfMissing: createIfMissing,
  );
  if (!opened) {
    return false;
  }

  try {
    await ref.read(autoSaveNotifierProvider.notifier).cancelPendingAndWait();
  } catch (_) {
    // ignore
  }
  final existingName = savedWorkspaceNameForPath(
    ref.read(settingsProvider).savedWorkspaces,
    path,
  );
  await ref.read(settingsProvider.notifier).rememberWorkspace(
        path: path,
        name: existingName ?? p.basename(path),
      );
  resetWorkspaceSelectionState(ref);
  await SchedulerBinding.instance.endOfFrame;
  invalidateWorkspaceProviders(ref);
  ref.invalidate(gitStatusProvider);
  return true;
}

Future<bool> activateClonedWorkspace(WidgetRef ref, String path) async {
  final opened = await initWorkspaceStorage(
    kIsDesktop,
    path,
    createIfMissing: false,
  );
  if (!opened) {
    return false;
  }

  final name = p.basename(path);

  try {
    await ref.read(autoSaveNotifierProvider.notifier).cancelPendingAndWait();
  } catch (_) {
    // ignore
  }

  ref.read(saveDataStateProvider.notifier).state = true;
  ref.read(hasUnsavedChangesProvider.notifier).state = false;
  resetWorkspaceSelectionState(ref);
  await SchedulerBinding.instance.endOfFrame;
  invalidateWorkspaceProviders(ref);

  await ref.read(settingsProvider.notifier).rememberWorkspace(
        path: path,
        name: name,
      );

  // Keep autosave off until collection/environment microtasks hydrate from disk.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await SchedulerBinding.instance.endOfFrame;

  ref.read(hasUnsavedChangesProvider.notifier).state = false;
  ref.read(saveDataStateProvider.notifier).state = false;
  ref.invalidate(gitStatusProvider);
  return true;
}
