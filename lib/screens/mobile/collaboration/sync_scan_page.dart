import 'dart:io';
import 'package:apidash/consts.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/services/services.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/models/sync_models.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:apidash/sync/sync_scan.dart';
import 'package:apidash/sync/sync_workspace_path.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
import 'package:apidash/sync/widgets/sync_adopt_workspace_sheet.dart';
import 'package:apidash/sync/widgets/sync_scan_overlay.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;

import '../workspace/mobile_workspace_service.dart';
import 'sync_session_page.dart';

class SyncScanPage extends ConsumerStatefulWidget {
  const SyncScanPage({super.key});

  @override
  ConsumerState<SyncScanPage> createState() => _SyncScanPageState();
}

class _SyncScanPageState extends ConsumerState<SyncScanPage> {
  static const _invalidQrCooldown = Duration(seconds: 3);

  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false;
  String? _lastInvalidRaw;
  DateTime? _lastInvalidAt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final payload = SyncQrPayload.tryDecode(raw);
    if (payload == null) {
      final now = DateTime.now();
      if (_lastInvalidRaw == raw &&
          _lastInvalidAt != null &&
          now.difference(_lastInvalidAt!) < _invalidQrCooldown) {
        return;
      }
      _lastInvalidRaw = raw;
      _lastInvalidAt = now;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(getSnackBar(kErrSyncInvalidQr));
      return;
    }

    _lastInvalidRaw = null;
    _lastInvalidAt = null;

    _handled = true;

    final targetPath = await resolveMobileWorkspacePath(payload.workspaceId);
    final targetExists = Directory(targetPath).existsSync();

    final activePath = resolveSyncWorkspaceRoot(ref);
    final isActiveTarget =
        activePath != null && p.equals(activePath, targetPath);

    var scanCase = SyncScanCase.firstLink;
    if (targetExists) {
      final targetStorage = SyncStorage(targetPath);
      final targetLocal = await targetStorage.readWorkspace();
      final targetSync = await targetStorage.readSyncState();
      scanCase = resolveScanCase(
        localWorkspaceId: targetLocal?.id,
        qrWorkspaceId: payload.workspaceId,
        hasSyncedBaseline: targetSync?.hasBaseline ?? false,
      );
    }

    if (!mounted) {
      _handled = false;
      return;
    }

    final isIncremental = targetExists && !scanCaseNeedsAdoption(scanCase);

    if (isIncremental) {
      if (isActiveTarget) {
        await _openSession(payload, SyncSessionMode.incremental);
        return;
      }
      final currentName = savedWorkspaceNameForPath(
            ref.read(settingsProvider).savedWorkspaces,
            activePath,
          ) ??
          kLabelSelectWorkspace;
      final proceed = await _confirm(
        title: 'Sync ${payload.workspaceName}?',
        body:
            "From ${payload.desktopName}.\nYou're currently in $currentName - "
            "we'll switch to ${payload.workspaceName} to sync.",
        confirmLabel: kLabelSyncSwitchAndSync,
      );
      if (!mounted) return;
      if (proceed != true) {
        setState(() => _handled = false);
        return;
      }
      final ok = await activateWorkspace(
        ref,
        targetPath,
        createIfMissing: false,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _handled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          getSnackBar(kMsgWorkspaceOpenFailed),
        );
        return;
      }
      await _openSession(payload, SyncSessionMode.incremental);
      return;
    }

    final createdId = await createMobileWorkspace(
      ref,
      id: payload.workspaceId,
      name: payload.workspaceName.isEmpty ? 'Workspace' : payload.workspaceName,
    );
    if (!mounted) return;
    if (createdId == null) {
      setState(() => _handled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        getSnackBar(kMsgWorkspaceCreateFailed),
      );
      return;
    }

    final adopted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => SyncAdoptWorkspaceSheet(qrPayload: payload),
    );

    if (!mounted) return;
    if (adopted == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        getSnackBar(kMsgSyncUpdateSuccess),
      );
      Navigator.pop(context);
      return;
    }

    if (!targetExists) {
      if (activePath != null && !p.equals(activePath, targetPath)) {
        await activateWorkspace(ref, activePath, createIfMissing: false);
      }
      await deleteMobileWorkspace(ref, targetPath);
    }
    if (mounted) setState(() => _handled = false);
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(kLabelCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSession(SyncQrPayload payload, SyncSessionMode mode) async {
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => SyncSessionPage(qrPayload: payload, mode: mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(kLabelSyncScanDesktop),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          const IgnorePointer(child: SyncScanOverlay()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: kP20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      kLabelSyncScanHint,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                
              ],
            ),
          ),
        ],
      ),
    );
  }
}
