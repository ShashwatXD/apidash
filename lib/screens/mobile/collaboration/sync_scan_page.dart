import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'sync_session_page.dart';

/// Full-screen QR scanner — connects to the desktop sync host.
class SyncScanPage extends StatefulWidget {
  const SyncScanPage({super.key});

  @override
  State<SyncScanPage> createState() => _SyncScanPageState();
}

class _SyncScanPageState extends State<SyncScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final payload = SyncQrPayload.tryDecode(raw);
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        getSnackBar(kErrSyncInvalidQr),
      );
      return;
    }

    _handled = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => SyncSessionPage(qrPayload: payload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(kLabelSyncScanDesktop),
        centerTitle: true,
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
      ),
    );
  }
}
