import 'dart:async';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/git/providers/git_status_provider.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:apidash/sync/providers/sync_providers.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/misc.dart' show ProviderListenable, ProviderOrFamily;

import 'auto_save.dart';
import 'active_collection_providers.dart';
import 'collection_catalog_providers.dart';
import 'environment_providers.dart';
import 'history_providers.dart';
import 'settings_providers.dart';
import 'ui_providers.dart';

final workspaceDiskReloadSuppressCountProvider = StateProvider<int>((ref) => 0);

const _kWorkspaceDiskSuppressTail = Duration(milliseconds: 1500);
const _kWorkspaceFolderPollInterval = Duration(seconds: 1);

typedef _WorkspaceReader = T Function<T>(ProviderListenable<T> provider);
typedef _WorkspaceInvalidator =
    void Function(ProviderOrFamily provider, {bool asReload});

bool _workspaceCloseInProgress = false;

String? _activeWorkspacePath(_WorkspaceReader read) {
  final path = read(settingsProvider).workspaceFolderPath;
  if (path == null || path.isEmpty) return null;
  return p.normalize(path);
}

bool workspaceFolderExistsOnDiskSync(Ref ref) {
  final path = _activeWorkspacePath(ref.read);
  if (path == null) return false;
  return Directory(path).existsSync();
}

Future<bool> _workspaceFolderExists(String path) =>
    Directory(p.normalize(path)).exists();

void beginWorkspaceDiskReloadSuppress(Ref ref) {
  _beginWorkspaceDiskReloadSuppress(ref.read);
}

void endWorkspaceDiskReloadSuppress(Ref ref) {
  _endWorkspaceDiskReloadSuppress(ref.read);
}

void _beginWorkspaceDiskReloadSuppress(_WorkspaceReader read) {
  read(workspaceDiskReloadSuppressCountProvider.notifier).state++;
}

void _endWorkspaceDiskReloadSuppress(_WorkspaceReader read) {
  Future<void>.delayed(_kWorkspaceDiskSuppressTail, () {
    final notifier = read(workspaceDiskReloadSuppressCountProvider.notifier);
    final next = notifier.state - 1;
    notifier.state = next < 0 ? 0 : next;
  });
}

Future<void> _ensureActiveWorkspaceStillOnDisk(Ref ref) async {
  if (_workspaceCloseInProgress) return;
  final path = _activeWorkspacePath(ref.read);
  if (path == null) return;
  if (!await _workspaceFolderExists(path)) {
    await closeActiveWorkspaceMissingOnDisk(ref);
  }
}

void _showWorkspaceMissingOnDiskSnackBar() {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    final messenger = kAppScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        getSnackBar(
          kMsgWorkspaceRecentMissing,
          color: kColorRed,
          small: false,
          duration: kWorkspaceMissingSnackDuration,
        ),
      );
  });
}

/// Clears the active workspace and returns the app to the workspace selector.
Future<void> closeActiveWorkspaceMissingOnDisk(Ref ref) async {
  if (_workspaceCloseInProgress) return;

  final path = _activeWorkspacePath(ref.read);
  if (path == null) return;

  _workspaceCloseInProgress = true;
  _beginWorkspaceDiskReloadSuppress(ref.read);
  try {
    await ref.read(autoSaveNotifierProvider.notifier).cancelPendingAndWait();
    ref.read(hasUnsavedChangesProvider.notifier).state = false;
    resetWorkspaceStorage();
    await ref
        .read(settingsProvider.notifier)
        .clearActiveWorkspace(removeFromRecents: true);
    _showWorkspaceMissingOnDiskSnackBar();
  } finally {
    _endWorkspaceDiskReloadSuppress(ref.read);
    _workspaceCloseInProgress = false;
  }
}

/// Detects when the workspace root folder is deleted externally.
///
/// Does not reload workspace data on file changes — that raced with autosave and
/// dropped in-memory requests. Disk → memory reload is only for explicit git ops.
final workspacePresenceWatchProvider = Provider<void>((ref) {
  if (!kIsDesktop) return;

  final path = ref.watch(
    settingsProvider.select((settings) => settings.workspaceFolderPath),
  );
  if (path == null || path.isEmpty) return;

  StreamSubscription<FileSystemEvent>? subscription;

  unawaited(_ensureActiveWorkspaceStillOnDisk(ref));

  final pollTimer = Timer.periodic(_kWorkspaceFolderPollInterval, (_) {
    unawaited(_ensureActiveWorkspaceStillOnDisk(ref));
  });

  try {
    subscription = Directory(path)
        .watch(recursive: true)
        .listen(
          (_) {},
          onError: (_) => unawaited(_ensureActiveWorkspaceStillOnDisk(ref)),
          onDone: () => unawaited(_ensureActiveWorkspaceStillOnDisk(ref)),
        );
  } catch (_) {
    unawaited(closeActiveWorkspaceMissingOnDisk(ref));
    return;
  }

  ref.onDispose(() {
    pollTimer.cancel();
    subscription?.cancel();
  });
});

/// Reloads workspace providers from disk. Called only from explicit git flows
/// (pull, checkout, restore) — never from passive filesystem watching.
Future<void> reloadWorkspaceFromDisk(WidgetRef ref) =>
    _reloadWorkspaceFromDisk(ref.read, ref.invalidate);

Future<void> reloadWorkspaceFromDiskRef(Ref ref) async {
  final path = _activeWorkspacePath(ref.read);
  if (path != null && !await _workspaceFolderExists(path)) {
    await closeActiveWorkspaceMissingOnDisk(ref);
    return;
  }
  await _reloadWorkspaceFromDisk(ref.read, ref.invalidate);
}

Future<void> _reloadWorkspaceFromDisk(
  _WorkspaceReader read,
  _WorkspaceInvalidator invalidate,
) async {
  _beginWorkspaceDiskReloadSuppress(read);
  try {
    read(autoSaveNotifierProvider.notifier).cancelPending();
    read(hasUnsavedChangesProvider.notifier).state = false;
    _resetWorkspaceSelectionState(read);
    await SchedulerBinding.instance.endOfFrame;
    _invalidateWorkspaceProviders(invalidate);
    invalidate(gitStatusProvider);
    read(gitDiskRevisionProvider.notifier).bump();
  } finally {
    _endWorkspaceDiskReloadSuppress(read);
  }
}

void resetWorkspaceSelectionState(WidgetRef ref) {
  _resetWorkspaceSelectionState(ref.read);
}

void _resetWorkspaceSelectionState(_WorkspaceReader read) {
  if (!isWorkspaceStorageInitialized()) {
    return;
  }
  final index = workspaceStorage.getCollectionsIndex();
  final firstCollectionId = index.isNotEmpty ? index.first.id : null;
  read(selectedCollectionIdStateProvider.notifier).state = firstCollectionId;
  read(selectedIdStateProvider.notifier).state = null;
  read(selectedEnvironmentIdStateProvider.notifier).state =
      kGlobalEnvironmentId;
  read(selectedHistoryIdStateProvider.notifier).state = null;
  read(selectedHistoryRequestModelProvider.notifier).state = null;
  read(requestSequenceProvider.notifier).state = [];
  read(expandedCollectionIdsProvider.notifier).state =
      firstCollectionId != null ? {firstCollectionId} : {};
  final settings = read(settingsProvider);
  if (settings.activeEnvironmentId != kGlobalEnvironmentId) {
    unawaited(
      read(
        settingsProvider.notifier,
      ).update(activeEnvironmentId: kGlobalEnvironmentId),
    );
  }
}

void invalidateWorkspaceProviders(WidgetRef ref) =>
    _invalidateWorkspaceProviders(ref.invalidate);

void _invalidateWorkspaceProviders(_WorkspaceInvalidator invalidate) {
  invalidate(collectionCatalogProvider);
  invalidate(activeCollectionProvider);
  invalidate(environmentsStateNotifierProvider);
  invalidate(historyMetaStateNotifier);
  invalidate(syncUnsyncedCountProvider);
}

Future<void> clearAllWorkspaceData(WidgetRef ref) async {
  if (!isWorkspaceStorageInitialized()) {
    return;
  }

  ref.read(clearDataStateProvider.notifier).state = true;
  ref.read(saveDataStateProvider.notifier).state = true;
  ref.read(hasUnsavedChangesProvider.notifier).state = false;

  try {
    ref.read(autoSaveNotifierProvider.notifier).cancelPending();

    final root = workspaceStorage.rootPath;
    await SyncStorage(root).deleteApidashDir();
    await workspaceStorage.clear();

    invalidateWorkspaceProviders(ref);
    ref.invalidate(gitStatusProvider);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await SchedulerBinding.instance.endOfFrame;
  } finally {
    ref.read(hasUnsavedChangesProvider.notifier).state = false;
    ref.read(clearDataStateProvider.notifier).state = false;
    ref.read(saveDataStateProvider.notifier).state = false;
  }
}
