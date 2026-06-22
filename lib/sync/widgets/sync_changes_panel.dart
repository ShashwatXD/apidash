import 'package:apidash/git/models/git_change_tree.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/widgets/git_changes_tree.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/models/sync_models.dart';
import 'package:apidash/sync/sync_change_adapter.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

class SyncChangesPanel extends StatelessWidget {
  const SyncChangesPanel({
    super.key,
    required this.isConnected,
    required this.incoming,
    required this.conflicts,
    required this.acceptedPaths,
    required this.previewPath,
    required this.onSelectionChanged,
    required this.onFilePreview,
    this.sessionHint,
  });

  final bool isConnected;
  final List<SyncFileChange> incoming;
  final List<SyncFileChange> conflicts;
  final Set<String> acceptedPaths;
  final String? previewPath;
  final String? sessionHint;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<GitChange> onFilePreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!isConnected) {
      return Center(
        child: Padding(
          padding: kP20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sync_disabled_rounded,
                size: 36,
                color: scheme.outline.withValues(alpha: 0.65),
              ),
              kVSpacer10,
              Text(
                kLabelSyncWaitingForChanges,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final reviewable = [...incoming, ...conflicts];
    final hasReviewable = reviewable.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            hasReviewable
                ? (conflicts.isNotEmpty && incoming.isEmpty
                    ? kLabelSyncConflicts
                    : kLabelSyncIncomingFromPhone)
                : kLabelSyncNoChanges,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (sessionHint != null && hasReviewable)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              sessionHint!,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        if (hasReviewable)
          Expanded(
            child: GitChangesTree(
              roots: buildGitChangeTree(syncChangesToGitChanges(reviewable)),
              selectedPaths: acceptedPaths,
              previewPath: previewPath,
              busy: false,
              onSelectionChanged: onSelectionChanged,
              onFilePreview: onFilePreview,
            ),
          )
        else
          Expanded(
            child: Center(
              child: Padding(
                padding: kP20,
                child: Text(
                  kLabelSyncNoChanges,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
