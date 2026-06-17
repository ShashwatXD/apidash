import 'package:apidash/consts.dart';
import 'package:apidash/providers/settings_providers.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:apidash/sync/sync_apply.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncUnsyncedCountProvider = FutureProvider<int>((ref) async {
  String? workspacePath;
  if (kIsMobile) {
    try {
      workspacePath = workspaceStorage.rootPath;
    } catch (_) {
      return 0;
    }
  } else {
    workspacePath = ref.watch(
      settingsProvider.select((settings) => settings.workspaceFolderPath),
    );
  }
  if (workspacePath == null || workspacePath.isEmpty) {
    return 0;
  }
  return countUnsyncedOutgoingChanges(workspacePath);
});

Future<void> invalidateSyncUnsyncedCount(WidgetRef ref) async {
  ref.invalidate(syncUnsyncedCountProvider);
}
