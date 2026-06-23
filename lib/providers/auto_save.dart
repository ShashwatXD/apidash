import 'dart:async';

import 'package:apidash_core/apidash_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../consts.dart';
import '../models/models.dart';
import 'collection_providers.dart';
import 'collections_providers.dart';
import 'environment_providers.dart';
import 'package:apidash/git/providers/git_status_provider.dart';
import 'ui_providers.dart';

final autoSaveNotifierProvider =
    NotifierProvider<AutoSaveNotifier, void>(AutoSaveNotifier.new);

class AutoSaveNotifier extends Notifier<void> {
  Timer? _timer;

  @override
  void build() {
    void onWorkspaceDataChanged() {
      if (ref.read(saveDataStateProvider) || ref.read(clearDataStateProvider)) {
        return;
      }
      _schedule();
    }

    ref.listen<Map<String, RequestModel>?>(
      collectionStateNotifierProvider,
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
      collectionsStateNotifierProvider,
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
    cancelPending();
    if (!force && !ref.read(hasUnsavedChangesProvider)) {
      return;
    }
    if (ref.read(saveDataStateProvider) || ref.read(clearDataStateProvider)) {
      return;
    }
    await ref.read(collectionStateNotifierProvider.notifier).saveData();
    await ref.read(collectionsStateNotifierProvider.notifier).saveCollections();
    await ref.read(environmentsStateNotifierProvider.notifier).saveEnvironments();
    ref.read(gitDiskRevisionProvider.notifier).bump();
    invalidateGitStatus(ref);
  }
}
