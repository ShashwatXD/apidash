import 'dart:async';

import 'package:apidash_core/apidash_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../consts.dart';
import '../models/models.dart';
import 'active_collection_providers.dart';
import 'collection_catalog_providers.dart';
import 'environment_providers.dart';
import 'package:apidash/git/providers/git_status_provider.dart';
import 'ui_providers.dart';
import 'workspace_lifecycle.dart';
import '../services/storage/workspace_storage.dart';

final autoSaveNotifierProvider =
    NotifierProvider<AutoSaveNotifier, void>(AutoSaveNotifier.new);

class AutoSaveNotifier extends Notifier<void> {
  Timer? _timer;
  bool _flushInProgress = false;
  bool _flushAgain = false;

  @override
  void build() {
    void onWorkspaceDataChanged() {
      if (ref.read(saveDataStateProvider) || ref.read(clearDataStateProvider)) {
        return;
      }
      _schedule();
    }

    ref.listen<Map<String, RequestModel>?>(
      activeCollectionProvider,
      (previous, next) {
        if (previous == null) {
          return;
        }
        onWorkspaceDataChanged();
      },
    );

    ref.listen<Map<String, EnvironmentModel>?>(
      environmentsStateNotifierProvider,
      (previous, next) {
        if (previous == null) {
          return;
        }
        onWorkspaceDataChanged();
      },
    );

    ref.listen<Map<String, CollectionModel>?>(
      collectionCatalogProvider,
      (previous, next) {
        if (previous == null) {
          return;
        }
        onWorkspaceDataChanged();
      },
    );

    ref.listen<List<String>>(collectionSequenceProvider, (previous, next) {
      if (previous == null) {
        return;
      }
      onWorkspaceDataChanged();
    });

    ref.listen<List<String>>(requestSequenceProvider, (previous, next) {
      if (previous == null) {
        return;
      }
      onWorkspaceDataChanged();
    });

    ref.listen<List<String>>(environmentSequenceProvider, (previous, next) {
      if (previous == null) {
        return;
      }
      onWorkspaceDataChanged();
    });

    ref.onDispose(() {
      _timer?.cancel();
    });
  }

  void cancelPending() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> cancelPendingAndWait() async {
    cancelPending();
    while (_flushInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(kAutoSaveDebounceDuration, () {
      unawaited(_flush());
    });
    Future.microtask(() {
      if (ref.read(saveDataStateProvider)) {
        return;
      }
      ref.read(hasUnsavedChangesProvider.notifier).state = true;
    });
  }

  /// Persist pending edits to disk immediately (e.g. before git commit).
  Future<void> flushNow({bool force = false}) => _flush(force: force);

  Future<void> _flush({bool force = false}) async {
    if (!ref.mounted) return;
    if (_flushInProgress) {
      _flushAgain = true;
      return;
    }
    cancelPending();
    if (!force && !ref.read(hasUnsavedChangesProvider)) {
      return;
    }
    if (ref.read(saveDataStateProvider) || ref.read(clearDataStateProvider)) {
      return;
    }
    if (!workspaceFolderExistsOnDiskSync(ref)) {
      await closeActiveWorkspaceMissingOnDisk(ref);
      return;
    }
    if (!isWorkspaceStorageInitialized()) {
      return;
    }

    _flushInProgress = true;
    beginWorkspaceDiskReloadSuppress(ref);
    try {
      if (!ref.mounted) return;
      await ref.read(activeCollectionProvider.notifier).saveData();
      if (!ref.mounted) return;
      await ref.read(collectionCatalogProvider.notifier).saveCollections();
      if (!ref.mounted) return;
      await ref
          .read(environmentsStateNotifierProvider.notifier)
          .saveEnvironments();
      if (!ref.mounted) return;
      ref.read(gitDiskRevisionProvider.notifier).bump();
      invalidateGitStatus(ref);
      ref.read(hasUnsavedChangesProvider.notifier).state = false;
    } catch (e, st) {
      debugPrint('AutoSaveNotifier._flush failed: $e\n$st');
    } finally {
      endWorkspaceDiskReloadSuppress(ref);
      _flushInProgress = false;
      if (_flushAgain && ref.mounted) {
        _flushAgain = false;
        if (ref.read(hasUnsavedChangesProvider)) {
          unawaited(_flush(force: force));
        }
      } else {
        _flushAgain = false;
      }
    }
  }
}
