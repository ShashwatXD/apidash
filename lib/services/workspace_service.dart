import 'package:apidash/consts.dart';
import 'package:apidash/providers/auto_save.dart';
import 'package:apidash/git/providers/git_status_provider.dart';
import 'package:apidash/providers/settings_providers.dart';
import 'package:apidash/providers/ui_providers.dart';
import 'package:apidash/providers/workspace_lifecycle.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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
    ref.read(autoSaveNotifierProvider.notifier).cancelPending();
  } catch (_) {
    // ignore
  }
  final name = p.basename(path);
  await ref.read(settingsProvider.notifier).rememberWorkspace(
        path: path,
        name: name,
      );
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

  ref.read(saveDataStateProvider.notifier).state = true;
  ref.read(hasUnsavedChangesProvider.notifier).state = false;
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
