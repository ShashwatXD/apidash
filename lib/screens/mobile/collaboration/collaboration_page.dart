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
    final workspacePath = resolveSyncWorkspaceRoot(ref);
    final unsynced = ref.watch(syncUnsyncedCountProvider);

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainerLowest,
        leading: BackButton(
          onPressed: () => ref.read(navRailIndexStateProvider.notifier).state = 0,
        ),
        title: const Text('Collab'),
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
                final isPaired = status?.isPaired ?? false;

                return ListView(
                  padding: kPh20,
                  children: [
                    kVSpacer20,
                    const _SyncHeroHeader(),
                    if (!isPaired) ...[
                      kVSpacer20,
                      const _CompactHowItWorks(),
                    ] else if (status?.workspaceName != null) ...[
                      kVSpacer16,
                      _StatusCard(
                        workspaceName: status!.workspaceName!,
                        desktopName: status.desktopName,
                        lastSyncAt: status.lastSyncAt,
                      ),
                    ],
                    kVSpacer20,
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
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                        label: const Text(kLabelSyncScanDesktop),
                      ),
                    ),
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
      isPaired: sync?.hasBaseline ?? false,
    );
  }
}

class _SyncHeroHeader extends StatelessWidget {
  const _SyncHeroHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Icon(
              Icons.cloud_sync,
              size: 48,
              color: scheme.primary,
            ),
          ),
        ),
        kVSpacer16,
        Text(
          'Sync with your Desktop',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall,
        ),
      ],
    );
  }
}

class _CompactHowItWorks extends StatelessWidget {
  const _CompactHowItWorks();

  static const _steps = [
    'Open Collaboration on your computer',
    'Connect on the same Wi‑Fi and scan the QR',
    'Review changes and apply on your phone',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: kBorderRadius12,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: kP12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                kHSpacer8,
                Text(
                  'How it works',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            kVSpacer10,
            for (var i = 0; i < _steps.length; i++) ...[
              if (i > 0) kVSpacer10,
              _HowItWorksStep(
                index: i + 1,
                label: _steps[i],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({
    required this.index,
    required this.label,
  });

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: scheme.primaryContainer.withValues(alpha: 0.55),
          child: Text(
            '$index',
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
        kHSpacer10,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                height: 1.35,
              ),
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
    this.isPaired = false,
  });

  final String? workspaceName;
  final String? desktopName;
  final String? lastSyncAt;
  final bool isPaired;
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: kBorderRadius12,
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
                Icons.folder_outlined,
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
                  workspaceName,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (desktopName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Paired with $desktopName',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
                if (lastSyncLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    lastSyncLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
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
