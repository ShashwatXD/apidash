import 'package:apidash/git/providers/git_status_provider.dart';
import 'package:apidash/services/services.dart';
import 'package:apidash/sync/providers/sync_providers.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;

import 'auto_save.dart';
import 'collection_providers.dart';
import 'collections_providers.dart';
import 'environment_providers.dart';
import 'history_providers.dart';
import 'ui_providers.dart';

Future<void> reloadWorkspaceFromDisk(WidgetRef ref) async {
  try {
    ref.read(autoSaveNotifierProvider.notifier).cancelPending();
  } catch (_) {
    // ignore
  }
  invalidateWorkspaceProviders(ref);
}

void invalidateWorkspaceProviders(WidgetRef ref) {
  ref.invalidate(collectionsStateNotifierProvider);
  ref.invalidate(collectionStateNotifierProvider);
  ref.invalidate(environmentsStateNotifierProvider);
  ref.invalidate(historyMetaStateNotifier);
  ref.invalidate(selectedIdStateProvider);
  ref.invalidate(selectedCollectionIdStateProvider);
  ref.invalidate(selectedEnvironmentIdStateProvider);
  ref.invalidate(selectedHistoryIdStateProvider);
  ref.invalidate(selectedHistoryRequestModelProvider);
  ref.invalidate(requestSequenceProvider);
  ref.invalidate(expandedCollectionIdsProvider);
  ref.invalidate(syncUnsyncedCountProvider);
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
