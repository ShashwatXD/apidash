import 'package:apidash/consts.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/providers/providers.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GitStatusBadge extends ConsumerWidget {
  const GitStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsDesktop) return const SizedBox.shrink();

    ref.watch(gitWorkspaceWatchProvider);
    final statusAsync = ref.watch(gitStatusProvider);
    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (status) {
        if (!status.gitInstalled ||
            !status.isRepository ||
            status.remoteUrl == null) {
          return const SizedBox.shrink();
        }
        final branch = _branchLabel(status);
        if (branch == null) {
          return const SizedBox.shrink();
        }
        final dotColor = _dotColor(status.syncState);
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: 'Open Collaboration ($branch)',
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                ref.read(navRailIndexStateProvider.notifier).state =
                    kNavRailCollaborationIndex;
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  kHSpacer4,
                  Text(
                    branch,
                    style: Theme.of(context).textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _dotColor(GitSyncState state) {
    return switch (state) {
      GitSyncState.clean => kColorStatusCode200,
      GitSyncState.dirty || GitSyncState.ahead => kColorStatusCode500,
      GitSyncState.behind || GitSyncState.diverged => kColorStatusCode300,
      GitSyncState.error => kColorStatusCode400,
      _ => kColorStatusCodeDefault,
    };
  }

  String? _branchLabel(GitStatus status) {
    final current = status.branch;
    if (current != null && current.isNotEmpty && current != 'HEAD') {
      return current;
    }
    for (final name in status.branches) {
      if (name.isNotEmpty && name != 'HEAD') return name;
    }
    return null;
  }
}
