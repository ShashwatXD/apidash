import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/models/sync_models.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:apidash/sync/sync_scan.dart';
import 'package:apidash/sync/sync_workspace_path.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
import 'package:apidash/sync/widgets/sync_scan_overlay.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
    final workspacePath = resolveSyncWorkspaceRoot(ref);
    if (workspacePath == null) {
      _handled = false;
      return;
    }

    final storage = SyncStorage(workspacePath);
    final local = await storage.readWorkspace();
    final scanCase = resolveScanCase(
      localWorkspaceId: local?.id,
      qrWorkspaceId: payload.workspaceId,
    );

    if (!mounted) {
      _handled = false;
      return;
    }

    if (!scanCaseNeedsAdoption(scanCase)) {
      await _openSession(payload, SyncSessionMode.incremental);
      return;
    }

    final adopt = await _showAdoptWorkspaceSheet(payload);

    if (adopt != true) {
      if (mounted) {
        setState(() => _handled = false);
        Navigator.pop(context);
      }
      return;
    }

    await wipePhoneWorkspaceData(workspacePath);
    await adoptWorkspaceIdentity(
      workspacePath,
      identity: WorkspaceIdentity(
        id: payload.workspaceId,
        name: payload.workspaceName,
      ),
    );
    if (!mounted) return;
    await _openSession(payload, SyncSessionMode.workspaceReplace);
  }

  Future<bool?> _showAdoptWorkspaceSheet(SyncQrPayload payload) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.folder_copy_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              kVSpacer10,
              Text(
                kLabelSyncAdoptWorkspaceTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              kVSpacer10,
              Text(
                '${payload.workspaceName} on ${payload.desktopName}.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              kVSpacer8,
              Text(
                kLabelSyncAdoptWorkspaceBody,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              kVSpacer16,
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(kLabelSyncAdoptWorkspaceCancel),
                    ),
                  ),
                  kHSpacer8,
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(kLabelSyncAdoptWorkspaceConfirm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
