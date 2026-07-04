import 'dart:async';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/providers/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/git_models.dart';
import '../services/git_service.dart';

final gitServiceProvider = Provider<GitService>((ref) => GitService());

final gitStatusProvider =
    FutureProvider.autoDispose<GitStatus>((ref) async {
  if (!kIsDesktop) return GitStatus.empty;
  final path = ref.watch(
    settingsProvider.select((settings) => settings.workspaceFolderPath),
  );
  if (path == null || path.isEmpty) return GitStatus.empty;
  return ref.read(gitServiceProvider).getStatus(path);
});

final gitWorkspaceWatchProvider = Provider<void>((ref) {
  if (!kIsDesktop) return;

  final path = ref.watch(
    settingsProvider.select((settings) => settings.workspaceFolderPath),
  );
  if (path == null || path.isEmpty) return;

  Timer? debounce;
  StreamSubscription<FileSystemEvent>? subscription;

  try {
    subscription = Directory(path).watch(recursive: true).listen((_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 800), () {
        ref.invalidate(gitStatusProvider);
      });
    });
  } catch (_) {
    return;
  }

  ref.onDispose(() {
    debounce?.cancel();
    subscription?.cancel();
  });
});

void invalidateGitStatus(Ref ref) {
  ref.invalidate(gitStatusProvider);
}

final gitDiskRevisionProvider =
    NotifierProvider<GitDiskRevisionNotifier, int>(GitDiskRevisionNotifier.new);

class GitDiskRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
