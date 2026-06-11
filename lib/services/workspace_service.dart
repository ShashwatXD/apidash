import 'package:apidash/consts.dart';
import 'package:apidash/providers/auto_save.dart';
import 'package:apidash/providers/git_status_provider.dart';
import 'package:apidash/providers/settings_providers.dart';
import 'package:apidash/providers/workspace_lifecycle.dart';
import 'package:apidash/services/storage/workspace_meta.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> activateWorkspace(
  WidgetRef ref,
  String path, {
  String? preferredName,
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
  final name = await ensureAndReadWorkspaceName(
    path,
    preferredName: preferredName,
  );
  await ref.read(settingsProvider.notifier).rememberWorkspace(
        path: path,
        name: name,
      );
  invalidateWorkspaceProviders(ref);
  ref.invalidate(gitStatusProvider);
  return true;
}
