import 'package:apidash/git/git_workspace_guard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auto_save.dart';
import 'git_status_provider.dart';
import 'settings_providers.dart';
import 'workspace_lifecycle.dart';

export 'git_status_provider.dart';

Future<void> gitPull(WidgetRef ref) async {
  final path = ref.read(settingsProvider).workspaceFolderPath;
  if (path == null || path.isEmpty) return;

  await ref.read(autoSaveNotifierProvider.notifier).flushNow();
  await ref.read(gitServiceProvider).pull(path);
  await reloadWorkspaceFromDisk(ref);
  await _reloadGitStatus(ref);
}

Future<void> refreshGitStatus(WidgetRef ref) => _reloadGitStatus(ref);

Future<void> _reloadGitStatus(WidgetRef ref) async {
  ref.invalidate(gitStatusProvider);
  await ref.read(gitStatusProvider.future);
}

Future<void> gitSync(
  WidgetRef ref, {
  required String message,
  required List<String> paths,
}) async {
  final path = ref.read(settingsProvider).workspaceFolderPath;
  if (path == null || path.isEmpty) return;
  if (paths.isEmpty) {
    throw StateError('Select at least one change to sync');
  }

  await ref.read(autoSaveNotifierProvider.notifier).flushNow();

  final unsafe = findUnsafeSecretEnvFiles(path, paths);
  if (unsafe.isNotEmpty) {
    throw StateError(
      'Cannot sync: secret values in ${unsafe.first}. Remove secrets before committing.',
    );
  }

  final git = ref.read(gitServiceProvider);
  await git.stage(path, paths);
  await git.commit(path, message);
  await git.push(path);
  await _reloadGitStatus(ref);
}

Future<void> gitInitRepository(WidgetRef ref) async {
  final path = ref.read(settingsProvider).workspaceFolderPath;
  if (path == null || path.isEmpty) return;
  await ref.read(gitServiceProvider).initRepository(path);
  await _reloadGitStatus(ref);
}

Future<void> gitSetRemote(WidgetRef ref, String url) async {
  final path = ref.read(settingsProvider).workspaceFolderPath;
  if (path == null || path.isEmpty) return;
  await ref.read(gitServiceProvider).setRemoteUrl(path, url);
  await _reloadGitStatus(ref);
}
