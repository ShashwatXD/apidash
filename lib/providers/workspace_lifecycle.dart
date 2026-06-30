import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show WidgetRef;

import 'auto_save.dart';
import 'active_collection_providers.dart';
import 'collection_catalog_providers.dart';
import 'environment_providers.dart';
import 'history_providers.dart';

Future<void> reloadWorkspaceFromDisk(WidgetRef ref) async {
  try {
    ref.read(autoSaveNotifierProvider.notifier).cancelPending();
  } catch (_) {
    // ignore
  }
  invalidateWorkspaceProviders(ref);
}

void invalidateWorkspaceProviders(WidgetRef ref) {
  ref.invalidate(collectionCatalogProvider);
  ref.invalidate(activeCollectionProvider);
  ref.invalidate(environmentsStateNotifierProvider);
  ref.invalidate(historyMetaStateNotifier);
  ref.invalidate(selectedIdStateProvider);
  ref.invalidate(selectedCollectionIdStateProvider);
  ref.invalidate(selectedEnvironmentIdStateProvider);
  ref.invalidate(selectedHistoryIdStateProvider);
  ref.invalidate(selectedHistoryRequestModelProvider);
  ref.invalidate(requestSequenceProvider);
  ref.invalidate(expandedCollectionIdsProvider);
}
