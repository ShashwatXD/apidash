import 'package:apidash/git/models/git_change_tree.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/widgets/git_changes_tree.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/models/sync_models.dart';
import 'package:apidash/sync/sync_change_adapter.dart';
import 'package:apidash/sync/sync_session_compute.dart';
import 'package:apidash/sync/widgets/sync_info_banner.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

/// Shared Send / Receive panel for desktop and mobile incremental sync.
class SyncDirectionPanel extends StatelessWidget {
  const SyncDirectionPanel({
    super.key,
    required this.isConnected,
    required this.isHost,
    required this.changeSet,
    required this.directionMode,
    required this.previewPath,
    required this.onDirectionModeChanged,
    required this.onFilePreview,
  });

  final bool isConnected;
  final bool isHost;
  final SyncChangeSet changeSet;
  final SyncDirectionMode directionMode;
  final String? previewPath;
  final ValueChanged<SyncDirectionMode> onDirectionModeChanged;
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

    final activeChanges = changesForDirection(changeSet, directionMode);
    final overlap = overlappingForDirection(changeSet, directionMode);
    final overlapMessage = overlapWarningMessage(
      mode: directionMode,
      overlapping: overlap,
      isHost: isHost,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Text(
            directionSummary(changeSet: changeSet, isHost: isHost),
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<SyncDirectionMode>(
            segments: const [
              ButtonSegment(
                value: SyncDirectionMode.send,
                label: Text(kLabelSyncSend),
                icon: Icon(Icons.upload_rounded, size: 18),
              ),
              ButtonSegment(
                value: SyncDirectionMode.receive,
                label: Text(kLabelSyncReceive),
                icon: Icon(Icons.download_rounded, size: 18),
              ),
            ],
            selected: {directionMode},
            onSelectionChanged: (selection) {
              onDirectionModeChanged(selection.first);
            },
          ),
        ),
        kVSpacer8,
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Text(
            directionListTitle(mode: directionMode, isHost: isHost),
            style: textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (overlapMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: SyncInfoBanner(message: overlapMessage),
          ),
        if (activeChanges.isEmpty)
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
          )
        else
          Expanded(
            child: GitChangesTree(
              roots: buildGitChangeTree(
                syncChangesToGitChanges(activeChanges),
              ),
              selectedPaths: activeChanges.map((c) => c.path).toSet(),
              previewPath: previewPath,
              busy: false,
              enableSelection: false,
              onSelectionChanged: (_) {},
              onFilePreview: onFilePreview,
            ),
          ),
      ],
    );
  }
}
