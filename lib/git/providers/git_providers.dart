import 'package:apidash/providers/auto_save.dart';
import 'package:apidash/providers/settings_providers.dart';
import 'package:apidash/providers/workspace_lifecycle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/git_workspace_guard.dart';
import 'git_status_provider.dart';

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

Future<String> gitCloneRepository(
  WidgetRef ref, {
  required String remoteUrl,
  required String parentDirectory,
}) async {
  final git = ref.read(gitServiceProvider);
  if (!await git.isGitInstalled()) {
    throw StateError('Git is not installed. Install Git to clone repositories.');
  }
  return git.clone(remoteUrl, parentDirectory);
}

Future<void> gitCheckoutBranch(WidgetRef ref, String branch) async {
  final path = ref.read(settingsProvider).workspaceFolderPath;
  if (path == null || path.isEmpty) return;

  await ref.read(autoSaveNotifierProvider.notifier).flushNow();
  await ref.read(gitServiceProvider).checkoutBranch(path, branch);
  await reloadWorkspaceFromDisk(ref);
  await _reloadGitStatus(ref);
}
