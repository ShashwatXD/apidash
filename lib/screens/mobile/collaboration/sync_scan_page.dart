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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        getSnackBar(kErrSyncNoWorkspace),
      );
      return;
    }

    final storage = SyncStorage(workspacePath);
    final local = await storage.readWorkspace();
    final syncState = await storage.readSyncState();
    final scanCase = resolveScanCase(
      localWorkspaceId: local?.id,
      qrWorkspaceId: payload.workspaceId,
      hasSyncedBaseline: syncState?.hasBaseline ?? false,
    );

    if (!mounted) {
      _handled = false;
      return;
    }

    if (!scanCaseNeedsAdoption(scanCase)) {
      await _openSession(payload, SyncSessionMode.incremental);
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
    } else {
      setState(() => _handled = false);
    }
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
