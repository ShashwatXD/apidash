import 'dart:async';

import 'package:apidash/git/models/git_change_tree.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/providers/providers.dart';
import 'package:apidash/git/widgets/git_changes_tree.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../consts.dart';
import '../models/sync_models.dart';
import '../providers/sync_providers.dart';
import '../storage/sync_storage.dart';
import '../sync_apply.dart';
import '../sync_change_adapter.dart';
import '../sync_display_name.dart';
import '../sync_manifest_builder.dart';
import '../sync_session_compute.dart';
import '../transport/sync_messages.dart';
import '../transport/sync_session_server.dart';
import 'sync_diff_panel.dart';

Future<void> showSyncHostDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const SyncHostDialog(),
  );
}

class SyncHostDialog extends ConsumerStatefulWidget {
  const SyncHostDialog({super.key});

  @override
  ConsumerState<SyncHostDialog> createState() => _SyncHostDialogState();
}

class _SyncHostDialogState extends ConsumerState<SyncHostDialog> {
  static final _emptyPeer = SyncPeerInfo(
    workspaceId: '',
    workspaceName: '',
    displayName: '',
  );

  SyncPeerInfo _peer = _emptyPeer;
  SyncChangeSet _changeSet = const SyncChangeSet();
  final Set<String> _acceptedPaths = {};
  SyncFileChange? _previewChange;
  Map<String, SyncFileChange> _changesByPath = {};

  SyncSessionServer? _server;
  SyncStorage? _storage;
  String? _workspacePath;
  SyncQrPayload? _qrPayload;
  bool _starting = true;
  bool _connected = false;
  bool _applying = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    _resetChangeSelection(const SyncChangeSet());
    unawaited(_startSession());
  }

  @override
  void dispose() {
    unawaited(_server?.stop());
    super.dispose();
  }

  Future<void> _startSession() async {
    final workspacePath = ref.read(settingsProvider).workspaceFolderPath;
    if (workspacePath == null || workspacePath.isEmpty) {
      setState(() {
        _starting = false;
        _startError = kErrSyncNoWorkspace;
      });
      return;
    }

    try {
      final storage = SyncStorage(workspacePath);
      final workspace = await storage.getOrCreateWorkspace();
      final manifest = await buildSyncManifest(workspacePath);

      final server = SyncSessionServer(
        storage: storage,
        workspace: workspace,
        localManifest: manifest,
        workspaceRoot: workspacePath,
        desktopName: syncLocalDisplayName(),
      );
      server.onPeerConnected = (peer, _) => setState(() {
        _peer = peer;
        _connected = true;
      });
      server.onPeerDisconnected = () => setState(() => _connected = false);
      server.onChangeSet = _handleChangeSet;
      server.onError = (msg) => setState(() => _startError = msg);
      server.onSessionExpired = _handleSessionExpired;
      server.onRemoteApplied = _handleRemoteApplied;

      final qr = await server.start();
      if (!mounted) {
        await server.stop();
        return;
      }
      setState(() {
        _server = server;
        _storage = storage;
        _workspacePath = workspacePath;
        _qrPayload = qr;
        _starting = false;
        _startError ??= qr == null ? kErrSyncServerStart : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = '$kErrSyncServerStart ($e)';
      });
    }
  }

  void _handleChangeSet(SyncChangeSet changeSet) {
    setState(() {
      _changeSet = changeSet;
      _resetChangeSelection(changeSet);
    });
  }

  void _resetChangeSelection(SyncChangeSet changeSet) {
    _changesByPath = syncChangesByPath([
      ...changeSet.incoming,
      ...changeSet.outgoing,
      ...changeSet.conflicts,
    ]);
    _acceptedPaths
      ..clear()
      ..addAll(defaultAcceptedPaths(changeSet));
    _previewChange = null;
  }

  void _handleSessionExpired() {
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(getSnackBar(kErrSyncSessionExpired));
  }

  Future<void> _handleRemoteApplied() async {
    await reloadWorkspaceFromDisk(ref);
    await refreshGitStatus(ref);
    await invalidateSyncUnsyncedCount(ref);
    if (!mounted) return;
    setState(() {
      _changeSet = const SyncChangeSet();
      _resetChangeSelection(const SyncChangeSet());
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(getSnackBar(kMsgSyncWorkspaceUpdated));
  }

  Future<void> _apply() async {
    final server = _server;
    final storage = _storage;
    final workspacePath = _workspacePath;
    if (server == null ||
        storage == null ||
        workspacePath == null ||
        !_connected ||
        _applying) {
      return;
    }

    if (!sessionHasWork(_changeSet, _acceptedPaths)) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _applying = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(autoSaveNotifierProvider.notifier).flushNow(force: true);
      final result = await applySyncSession(
        workspaceRoot: workspacePath,
        storage: storage,
        peer: _peer,
        changeSet: _changeSet,
        acceptedPaths: _acceptedPaths,
        transfer: server,
        peerManifest: server.peerManifest,
      );
      await reloadWorkspaceFromDisk(ref);
      await refreshGitStatus(ref);
      await invalidateSyncUnsyncedCount(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        getSnackBar(
          '$kMsgSyncApplySuccess '
          '(${result.appliedIncoming} from phone, ${result.sentOutgoing} to phone)',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      messenger.showSnackBar(getSnackBar('$kErrSyncApplyFailed: $e'));
    }
  }

  String _applyButtonLabel(bool canApply) {
    if (_applying) return kLabelSyncApplying;
    if (!canApply || _acceptedPaths.isEmpty) return kLabelSyncApplyChanges;
    return '$kLabelSyncApplyChanges (${_acceptedPaths.length})';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final incoming = _changeSet.incoming;
    final conflicts = _changeSet.conflicts;
    final hasWork = sessionHasWork(_changeSet, _acceptedPaths);
    final canApply = _connected && hasWork && !_applying;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: SizedBox(
          width: 960,
          height: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        kLabelSyncToPhone,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_applying)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    IconButton(
                      onPressed: _applying ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: kLabelSyncClose,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 280,
                      child: _buildQrPanel(scheme, textTheme),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 300,
                      child: _SyncChangesPanel(
                        isConnected: _connected,
                        incoming: incoming,
                        conflicts: conflicts,
                        acceptedPaths: _acceptedPaths,
                        previewPath: _previewChange?.path,
                        onSelectionChanged: (paths) {
                          setState(() {
                            _acceptedPaths
                              ..clear()
                              ..addAll(paths);
                          });
                        },
                        onFilePreview: (change) {
                          setState(() {
                            _previewChange = _changesByPath[change.path];
                          });
                        },
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: SyncDiffPanel(
                        change: _previewChange,
                        workspaceRoot: _workspacePath ?? '',
                        transfer: _server,
                        isHost: true,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _applying ? null : () => Navigator.pop(context),
                      child: const Text(kLabelSyncDiscardSession),
                    ),
                    kHSpacer8,
                    FilledButton(
                      onPressed: canApply ? _apply : null,
                      child: Text(_applyButtonLabel(canApply)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrPanel(ColorScheme scheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.25),
                ),
              ),
              child: _buildQrContent(scheme, textTheme),
            ),
          ),
          kVSpacer10,
          Text(
            _qrPayload != null ? kLabelSyncScanQr : kLabelSyncQrPlaceholder,
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (_connected) ...[
            kVSpacer8,
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_iphone_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                  kHSpacer10,
                  Expanded(
                    child: Text(
                      kLabelSyncConnectedTo,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQrContent(ColorScheme scheme, TextTheme textTheme) {
    if (_starting) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_qrPayload == null) {
      return Center(
        child: Text(
          _startError ?? kErrSyncServerStart,
          style: textTheme.labelMedium?.copyWith(color: scheme.error),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: QrImageView(
        data: _qrPayload!.encode(),
        version: QrVersions.auto,
        gapless: true,
        backgroundColor: Colors.white,
      ),
    );
  }
}

class _SyncChangesPanel extends StatelessWidget {
  const _SyncChangesPanel({
    required this.isConnected,
    required this.incoming,
    required this.conflicts,
    required this.acceptedPaths,
    required this.previewPath,
    required this.onSelectionChanged,
    required this.onFilePreview,
  });

  final bool isConnected;
  final List<SyncFileChange> incoming;
  final List<SyncFileChange> conflicts;
  final Set<String> acceptedPaths;
  final String? previewPath;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<GitChange> onFilePreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!isConnected) {
      return Center(
        child: Padding(
          padding: kP12,
          child: Text(
            kLabelSyncWaitingForChanges,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final reviewable = [...incoming, ...conflicts];
    final hasReviewable = reviewable.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasReviewable) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              conflicts.isNotEmpty && incoming.isEmpty
                  ? kLabelSyncConflicts
                  : kLabelSyncIncomingFromPhone,
              style: textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: GitChangesTree(
              roots: buildGitChangeTree(syncChangesToGitChanges(reviewable)),
              selectedPaths: acceptedPaths,
              previewPath: previewPath,
              busy: false,
              onSelectionChanged: onSelectionChanged,
              onFilePreview: onFilePreview,
            ),
          ),
        ],
        if (!hasReviewable)
          Expanded(
            child: Center(
              child: Text(
                kLabelSyncNoChanges,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
