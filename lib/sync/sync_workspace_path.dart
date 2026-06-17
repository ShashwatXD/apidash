import 'package:apidash/consts.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:apidash/providers/settings_providers.dart';

/// Workspace root used by sync on desktop (settings path) and mobile (documents).
String? resolveSyncWorkspaceRoot(WidgetRef ref) {
  if (kIsMobile) {
    try {
      return workspaceStorage.rootPath;
    } catch (_) {
      return null;
    }
  }
  final path = ref.read(settingsProvider).workspaceFolderPath;
  if (path == null || path.isEmpty) return null;
  return path;
}
