import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
import 'package:apidash/sync/widgets/sync_connected_badge.dart';
import 'package:apidash/sync/widgets/sync_connection_status_card.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SyncQrPanel extends StatelessWidget {
  const SyncQrPanel({
    super.key,
    required this.starting,
    required this.qrPayload,
    required this.startError,
    required this.connected,
    required this.peerDisplayName,
    required this.wasPairedBefore,
    this.isHost = false,
  });

  final bool starting;
  final SyncQrPayload? qrPayload;
  final String? startError;
  final bool connected;
  final String peerDisplayName;
  final bool wasPairedBefore;
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasQr = qrPayload != null && !starting;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _QrContent(
                      scheme: scheme,
                      textTheme: textTheme,
                      starting: starting,
                      qrPayload: qrPayload,
                      startError: startError,
                    ),
                    if (connected && hasQr)
                      const Positioned(
                        top: 0,
                        right: 0,
                        child: SyncConnectedBadge(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          kVSpacer10,
          if (!connected)
            Text(
              hasQr ? kLabelSyncScanQr : kLabelSyncQrPlaceholder,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          const Spacer(),
          SyncConnectionStatusCard(
            connected: connected,
            peerDisplayName: peerDisplayName,
            wasPairedBefore: wasPairedBefore,
            isHost: isHost,
          ),
        ],
      ),
    );
  }
}

class _QrContent extends StatelessWidget {
  const _QrContent({
    required this.scheme,
    required this.textTheme,
    required this.starting,
    required this.qrPayload,
    required this.startError,
  });

  final ColorScheme scheme;
  final TextTheme textTheme;
  final bool starting;
  final SyncQrPayload? qrPayload;
  final String? startError;

  @override
  Widget build(BuildContext context) {
    if (starting) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (qrPayload == null) {
      return Center(
        child: Padding(
          padding: kP12,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 36,
                color: scheme.error.withValues(alpha: 0.8),
              ),
              kVSpacer8,
              Text(
                startError ?? kErrSyncServerStart,
                style: textTheme.labelMedium?.copyWith(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return QrImageView(
                data: qrPayload!.encode(),
                version: QrVersions.auto,
                size: constraints.maxWidth,
                gapless: true,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              );
            },
          ),
        ),
      ),
    );
  }
}
