import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/models/sync_models.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:apidash/sync/sync_scan.dart';
import 'package:apidash/sync/sync_workspace_path.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
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
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false;
  bool _torchOn = false;

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(getSnackBar(kErrSyncInvalidQr));
      return;
    }

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

    final adopt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(kLabelSyncAdoptWorkspaceTitle),
        content: Text(
          '${payload.workspaceName} on ${payload.desktopName}.\n\n'
          '$kLabelSyncAdoptWorkspaceBody',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(kLabelSyncAdoptWorkspaceCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(kLabelSyncAdoptWorkspaceConfirm),
          ),
        ],
      ),
    );

    if (adopt != true) {
      if (mounted) Navigator.pop(context);
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

  Future<void> _openSession(SyncQrPayload payload, SyncSessionMode mode) async {
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => SyncSessionPage(qrPayload: payload, mode: mode),
      ),
    );
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(kLabelSyncScanDesktop),
        actions: [
          IconButton(
            onPressed: _toggleTorch,
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: kP20,
                  child: Text(
                    kLabelSyncScanHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: kP20,
                  child: Text(
                    kLabelSyncSameWifi,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
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
