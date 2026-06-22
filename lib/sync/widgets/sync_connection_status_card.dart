import 'package:apidash/sync/consts.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

class SyncConnectionStatusCard extends StatelessWidget {
  const SyncConnectionStatusCard({
    super.key,
    required this.connected,
    required this.peerDisplayName,
    required this.wasPairedBefore,
  });

  final bool connected;
  final String peerDisplayName;
  final bool wasPairedBefore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(
                connected
                    ? Icons.phone_iphone_rounded
                    : Icons.hourglass_empty_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          kHSpacer10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected
                      ? (peerDisplayName.isNotEmpty ? peerDisplayName : 'Phone')
                      : kLabelSyncWaitingForPhone,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (connected) ...[
                  const SizedBox(height: 2),
                  Text(
                    wasPairedBefore
                        ? kLabelSyncPairedBefore
                        : kLabelSyncFirstPair,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (connected)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
        ],
      ),
    );
  }
}
