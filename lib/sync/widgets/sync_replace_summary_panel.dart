import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

class SyncReplaceSummaryPanel extends StatelessWidget {
  const SyncReplaceSummaryPanel({
    super.key,
    required this.workspaceName,
    required this.desktopName,
    required this.fileCount,
  });

  final String workspaceName;
  final String desktopName;
  final int fileCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: kP20,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Icon(
                  Icons.folder_copy_rounded,
                  size: 36,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            kVSpacer16,
            Text(
              workspaceName,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            kVSpacer8,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$fileCount ${fileCount == 1 ? 'file' : 'files'} from $desktopName',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            kVSpacer16,
            Text(
              'Your phone will get a fresh copy of this workspace.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
