import 'package:apidash/consts.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mobile collaboration tab — LAN sync with desktop (no Git on mobile).
class MobileCollaborationPage extends ConsumerWidget {
  const MobileCollaborationPage({super.key, required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainerLowest,
        leading: BackButton(
          onPressed: () {
            ref.read(navRailIndexStateProvider.notifier).state = 0;
          },
        ),
        title: const Text(kLabelCollaboration),
        centerTitle: true,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: kLabelSyncScanDesktop,
          ),
          kHSpacer8,
        ],
      ),
    );
  }
}
