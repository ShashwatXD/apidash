import 'dart:async';

import 'package:apidash/providers/providers.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/models/sync_models.dart';
import 'package:apidash/sync/providers/sync_providers.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:apidash/sync/sync_apply.dart';
import 'package:apidash/sync/sync_display_name.dart';
import 'package:apidash/sync/sync_manifest_builder.dart';
import 'package:apidash/sync/sync_scan.dart';
import 'package:apidash/sync/sync_workspace_path.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
import 'package:apidash/sync/transport/sync_session_client.dart';
import 'package:apidash/sync/widgets/sync_info_banner.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncAdoptWorkspaceSheet extends ConsumerStatefulWidget {
  const SyncAdoptWorkspaceSheet({super.key, required this.qrPayload});

  final SyncQrPayload qrPayload;

  @override
  ConsumerState<SyncAdoptWorkspaceSheet> createState() =>
      _SyncAdoptWorkspaceSheetState();
}

class _SyncAdoptWorkspaceSheetState extends ConsumerState<SyncAdoptWorkspaceSheet> {
  static final _emptyPeer = SyncPeerInfo(
    workspaceId: '',
    workspaceName: '',
    displayName: '',
  );

  SyncPeerInfo _peer = _emptyPeer;
  SyncChangeSet _changeSet = const SyncChangeSet();

  SyncSessionClient? _client;
  SyncStorage? _storage;
  String? _workspacePath;
  bool _connecting = true;
  bool _connected = false;
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void dispose() {
    unawaited(_client?.disconnect());
    super.dispose();
  }

  Future<void> _connect() async {
    final workspacePath = resolveSyncWorkspaceRoot(ref);
    if (workspacePath == null) {
      setState(() {
        _connecting = false;
        _error = kErrSyncNoWorkspace;
      });
      return;
    }

    try {
      final storage = SyncStorage(workspacePath);
      final localWorkspace = await storage.readWorkspace();
      final syncState = await storage.readSyncState();
      final manifest = await buildSyncManifest(workspacePath);

      final client = SyncSessionClient(
        storage: storage,
        localManifest: manifest,
        workspaceRoot: workspacePath,
        qrPayload: widget.qrPayload,
        localDisplayName: syncLocalDisplayName(),
        localWorkspaceId: localWorkspace?.id ?? '',
        localHasBaseline: syncState?.hasBaseline ?? false,
        sessionMode: SyncSessionMode.workspaceReplace,
      );
      client.onPeerConnected = (peer, _) => setState(() {
        _peer = peer;
        _connected = true;
      });
      client.onPeerDisconnected = _handlePeerDisconnected;
      client.onChangeSet = (changeSet) => setState(() => _changeSet = changeSet);
      client.onError = (msg) => setState(() => _error = msg);

      await client.connect();
      if (!mounted) {
        await client.disconnect();
        return;
      }
      setState(() {
        _client = client;
        _storage = storage;
        _workspacePath = workspacePath;
        _connecting = false;
      });
    } catch (e, st) {
      debugPrint('SyncAdoptWorkspaceSheet._connect failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = '$kErrSyncConnectFailed ($e)';
      });
    }
  }

  void _handlePeerDisconnected() {
    if (!mounted || _applying) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _applying) return;
      Navigator.pop(context, false);
    });
  }

  Future<void> _apply() async {
    final client = _client;
    final storage = _storage;
    final workspacePath = _workspacePath;
    if (client == null ||
        storage == null ||
        workspacePath == null ||
        !_connected ||
        _applying) {
      return;
    }

    setState(() => _applying = true);
    try {
      await ref.read(autoSaveNotifierProvider.notifier).flushNow(force: true);
      await wipePhoneWorkspaceData(workspacePath);
      await applyReplaceFromPeer(
        workspaceRoot: workspacePath,
        storage: storage,
        peer: _peer,
        transfer: client,
        peerManifest: client.peerManifest,
      );
      await adoptWorkspaceIdentity(
        workspacePath,
        identity: WorkspaceIdentity(
          id: widget.qrPayload.workspaceId,
          name: widget.qrPayload.workspaceName,
        ),
      );
      await reloadWorkspaceFromDisk(ref);
      await invalidateSyncUnsyncedCount(ref);
      if (!mounted) return;
      _client = null;
      await client.endSession();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        getSnackBar('$kErrSyncUpdateFailed: $e'),
      );
    }
  }

  void _cancel() {
    if (_applying) return;
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canApply = _connected && !_applying && _error == null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.folder_copy_outlined,
                    size: 28,
                    color: scheme.primary,
                  ),
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
            kVSpacer8,
            Text(
              widget.qrPayload.workspaceName,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            kVSpacer6,
            Text(
              'From ${widget.qrPayload.desktopName}',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            kVSpacer10,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                kLabelSyncAdoptWorkspaceBody,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_connecting) ...[
              kVSpacer16,
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              kVSpacer8,
              Text(
                kLabelSyncConnecting,
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_error != null) ...[
              kVSpacer10,
              SyncInfoBanner(message: _error!, isError: true),
            ],

            kVSpacer16,
            FilledButton(
              onPressed: canApply ? _apply : null,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _applying
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Text(
                      _connecting
                          ? kLabelSyncConnecting
                          : kLabelSyncSwitchAndSync,
                    ),
            ),
            kVSpacer8,
            TextButton(
              onPressed: _applying ? null : _cancel,
              child: const Text(kLabelSyncAdoptWorkspaceCancel),
            ),
          ],
        ),
      ),
    );
  }
}
