import 'package:apidash/providers/providers.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/providers/sync_providers.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:apidash/sync/sync_workspace_path.dart';
import 'package:apidash/sync/widgets/sync_info_banner.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileCollaborationPage extends ConsumerWidget {
  const MobileCollaborationPage({super.key, required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final workspacePath = resolveSyncWorkspaceRoot(ref);
    final unsynced = ref.watch(syncUnsyncedCountProvider);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainerLowest,
        leading: BackButton(
          onPressed: () => ref.read(navRailIndexStateProvider.notifier).state = 0,
        ),
        title: const Text('Sync'),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: workspacePath == null
          ? Center(
              child: Padding(
                padding: kP20,
                child: SyncInfoBanner(
                  message: kErrSyncNoWorkspace,
                  isError: true,
                ),
              ),
            )
          : FutureBuilder(
              future: _loadStatus(workspacePath),
              builder: (context, snapshot) {
                final status = snapshot.data;
                return ListView(
                  padding: kP20,
                  children: [
                    _HeroHeader(scheme: scheme, textTheme: textTheme),
                    kVSpacer20,
                    const _StepsCard(),
                    kVSpacer16,
                    if (status?.workspaceName != null) ...[
                      _StatusCard(
                        workspaceName: status!.workspaceName!,
                        desktopName: status.desktopName,
                        lastSyncAt: status.lastSyncAt,
                      ),
                      kVSpacer10,
                    ],
                    unsynced.when(
                      data: (count) => count > 0
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SyncInfoBanner(
                                message: '$count $kLabelSyncUnsynced',
                              ),
                            )
                          : const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onScan,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text(kLabelSyncScanDesktop),
                      ),
                    ),
                    kVSpacer10,
                    SyncInfoBanner(message: kLabelSyncSameWifi),
                  ],
                );
              },
            ),
    );
  }

  Future<_CollabStatus> _loadStatus(String workspacePath) async {
    final storage = SyncStorage(workspacePath);
    final workspace = await storage.readWorkspace();
    final sync = await storage.readSyncState();
    return _CollabStatus(
      workspaceName: workspace?.name,
      desktopName: sync?.peerDisplayName,
      lastSyncAt: sync?.lastSyncAt,
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.scheme,
    required this.textTheme,
  });

  final ColorScheme scheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Icon(
              Icons.sync_rounded,
              size: 32,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        kVSpacer10,
        Text(
          'Sync with your computer',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        kVSpacer6,
        Text(
          kLabelMobileCollaborationHint,
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: kP12,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How it works',
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer10,
          const _StepRow(
            number: '1',
            label: 'Open Sync on your computer',
            icon: Icons.computer_rounded,
          ),
          kVSpacer10,
          const _StepRow(
            number: '2',
            label: 'Scan the QR code',
            icon: Icons.qr_code_scanner_rounded,
          ),
          kVSpacer10,
          const _StepRow(
            number: '3',
            label: 'Review changes and apply',
            icon: Icons.check_circle_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.label,
    required this.icon,
  });

  final String number;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            number,
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        kHSpacer10,
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        kHSpacer8,
        Expanded(
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _CollabStatus {
  const _CollabStatus({
    this.workspaceName,
    this.desktopName,
    this.lastSyncAt,
  });

  final String? workspaceName;
  final String? desktopName;
  final String? lastSyncAt;
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.workspaceName,
    this.desktopName,
    this.lastSyncAt,
  });

  final String workspaceName;
  final String? desktopName;
  final String? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    String? lastSyncLabel;
    if (lastSyncAt != null) {
      final parsed = DateTime.tryParse(lastSyncAt!);
      if (parsed != null) {
        lastSyncLabel =
            '$kLabelSyncLastSynced ${DateFormat.yMMMd().add_jm().format(parsed.toLocal())}';
      }
    }

    return Container(
      padding: kP12,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.folder_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          kHSpacer12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workspaceName,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (desktopName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Paired with $desktopName',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (lastSyncLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    lastSyncLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
