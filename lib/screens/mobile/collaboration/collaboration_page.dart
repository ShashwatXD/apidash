import 'package:apidash/providers/providers.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/providers/sync_providers.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:apidash/sync/sync_workspace_path.dart';
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
          ? const Center(child: Text(kErrSyncNoWorkspace))
          : FutureBuilder(
              future: _loadStatus(workspacePath),
              builder: (context, snapshot) {
                final status = snapshot.data;
                return ListView(
                  padding: kP20,
                  children: [
                    Text(
                      kLabelMobileCollaborationHint,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    kVSpacer16,
                    if (status?.workspaceName != null) ...[
                      _StatusCard(
                        workspaceName: status!.workspaceName!,
                        desktopName: status.desktopName,
                        lastSyncAt: status.lastSyncAt,
                      ),
                      kVSpacer8,
                    ],
                    unsynced.when(
                      data: (count) => count > 0
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                '$count ${kLabelSyncUnsynced}',
                                style: textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    FilledButton.icon(
                      onPressed: onScan,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text(kLabelSyncScanDesktop),
                    ),
                    kVSpacer16,
                    Text(
                      '${kLabelSyncSameWifi} · ${kLabelSyncSecretsNote}',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
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

    return Card(
      child: Padding(
        padding: kP20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              workspaceName,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (desktopName != null) ...[
              const SizedBox(height: 4),
              Text(
                desktopName!,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (lastSyncLabel != null) ...[
              const SizedBox(height: 4),
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
    );
  }
}
