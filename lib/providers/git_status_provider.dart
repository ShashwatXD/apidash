import 'package:apidash/consts.dart';
import 'package:apidash/git/git_models.dart';
import 'package:apidash/git/git_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_providers.dart';

final gitServiceProvider = Provider<GitService>((ref) => GitService());

final gitStatusProvider = FutureProvider.autoDispose<GitStatus>((ref) async {
  if (!kIsDesktop) return GitStatus.empty;
  final path = ref.watch(
    settingsProvider.select((settings) => settings.workspaceFolderPath),
  );
  if (path == null || path.isEmpty) return GitStatus.empty;
  return ref.read(gitServiceProvider).getStatus(path);
});

void invalidateGitStatus(Ref ref) {
  ref.invalidate(gitStatusProvider);
}
