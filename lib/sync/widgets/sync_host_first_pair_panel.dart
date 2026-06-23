import 'package:apidash/sync/consts.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

class SyncHostFirstPairPanel extends StatelessWidget {
  const SyncHostFirstPairPanel({
    super.key,
    required this.workspaceName,
    required this.fileCount,
    required this.peerDisplayName,
  });

  final String workspaceName;
  final int fileCount;
  final String peerDisplayName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final phoneLabel =
        peerDisplayName.isNotEmpty ? peerDisplayName : 'Phone';

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
                  Icons.phone_iphone_rounded,
                  size: 36,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            kVSpacer16,
            Text(
              kLabelSyncFirstPairDesktop,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            kVSpacer8,
            if (workspaceName.isNotEmpty) ...[
              Text(
                workspaceName,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              kVSpacer8,
            ],
            if (fileCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$fileCount ${fileCount == 1 ? 'file' : 'files'} ready to copy',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            kVSpacer16,
            Text(
              kLabelSyncFirstPairDesktopBody,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            kVSpacer10,
            Text(
              '$phoneLabel is connected - continue on your phone.',
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
