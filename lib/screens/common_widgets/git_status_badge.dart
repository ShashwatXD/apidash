import 'package:apidash/consts.dart';
import 'package:apidash/git/git_models.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GitStatusBadge extends ConsumerWidget {
  const GitStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsDesktop) return const SizedBox.shrink();

    final statusAsync = ref.watch(gitStatusProvider);
    return statusAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
      data: (status) {
        if (!status.gitInstalled || !status.isRepository) {
          return const SizedBox.shrink();
        }
        final branch = status.branch ?? 'branch';
        final dotColor = _dotColor(context, status.syncState);
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

  Color _dotColor(BuildContext context, GitSyncState state) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      GitSyncState.clean => Colors.green,
      GitSyncState.dirty || GitSyncState.ahead => Colors.amber,
      GitSyncState.behind || GitSyncState.diverged => Colors.blue,
      GitSyncState.error => scheme.error,
      _ => scheme.outline,
    };
  }
}
