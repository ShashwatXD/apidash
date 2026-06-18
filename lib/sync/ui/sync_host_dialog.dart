import 'dart:async';

import 'package:apidash/consts.dart';
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
import '../storage/peer_sync_store.dart';
import '../storage/sync_device_store.dart';
import '../sync_apply.dart';
import '../sync_change_adapter.dart';
import '../sync_manifest_builder.dart';
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
  static const _emptySession = SyncSessionPreview(
    peer: SyncPeerInfo(
      deviceId: '',
      displayName: '',
      syncWorkspaceId: '',
    ),
    changeSet: SyncChangeSet(),
    isConnected: false,
    wasPairedBefore: false,
  );

  SyncSessionPreview _session = _emptySession;
  final Set<String> _acceptedPaths = {};
  SyncFileChange? _previewChange;
  Map<String, SyncFileChange> _changesByPath = {};

  SyncSessionServer? _server;
  PeerSyncStore? _peerStore;
  SyncWorkspaceMeta? _workspaceMeta;
  String? _workspacePath;
  SyncQrPayload? _qrPayload;
  bool _starting = true;
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
      final peerStore = PeerSyncStore(workspacePath);
      final identity = await SyncDeviceStore(workspacePath).getOrCreate();
      final meta = await peerStore.getOrCreateMeta();
      final manifest = await buildSyncManifest(workspacePath);

      final server = SyncSessionServer(
        identity: identity,
        workspaceMeta: meta,
        localManifest: manifest,
        peerStore: peerStore,
        workspaceRoot: workspacePath,
      )
        ..onPeerConnected = _handlePeerConnected
        ..onPeerDisconnected = _handlePeerDisconnected
        ..onChangeSet = _handleChangeSet
        ..onError = _handleServerError
        ..onSessionExpired = _handleSessionExpired
        ..onRemoteApplied = _handleRemoteApplied;

      final qr = await server.start();
      if (!mounted) {
        await server.stop();
        return;
      }
      setState(() {
        _server = server;
        _peerStore = peerStore;
        _workspaceMeta = meta;
        _workspacePath = workspacePath;
        _qrPayload = qr;
        _starting = false;
        if (qr == null) {
          _startError ??= kErrSyncServerStart;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = '$kErrSyncServerStart ($e)';
      });
    }
  }

  void _handlePeerConnected(SyncPeerInfo peer, bool wasPairedBefore) {
    if (!mounted) return;
    setState(() {
      _session = SyncSessionPreview(
        peer: peer,
        changeSet: _session.changeSet,
        isConnected: true,
        wasPairedBefore: wasPairedBefore,
      );
    });
  }

  void _handlePeerDisconnected() {
    if (!mounted) return;
    setState(() {
      _session = SyncSessionPreview(
        peer: _session.peer,
        changeSet: _session.changeSet,
        isConnected: false,
        wasPairedBefore: _session.wasPairedBefore,
      );
    });
  }

  void _handleChangeSet(SyncChangeSet changeSet) {
    if (!mounted) return;
    setState(() {
      _session = SyncSessionPreview(
        peer: _session.peer,
        changeSet: changeSet,
        isConnected: _session.isConnected,
        wasPairedBefore: _session.wasPairedBefore,
      );
      _resetChangeSelection(changeSet);
    });
  }

  void _handleServerError(String message) {
    if (!mounted) return;
    setState(() => _startError = message);
  }

  void _handleSessionExpired() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(getSnackBar(kErrSyncSessionExpired));
  }

  Future<void> _handleRemoteApplied() async {
    if (!mounted) return;
    await reloadWorkspaceFromDisk(ref);
    await refreshGitStatus(ref);
    await invalidateSyncUnsyncedCount(ref);
    if (!mounted) return;
    setState(() {
      _session = SyncSessionPreview(
        peer: _session.peer,
        changeSet: const SyncChangeSet(),
        isConnected: _session.isConnected,
        wasPairedBefore: true,
      );
      _resetChangeSelection(const SyncChangeSet());
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(getSnackBar(kMsgSyncWorkspaceUpdated));
  }

  void _resetChangeSelection(SyncChangeSet changeSet) {
    _changesByPath = syncChangesByPath([
      ...changeSet.incoming,
      ...changeSet.outgoing,
      ...changeSet.conflicts,
    ]);
    _acceptedPaths
      ..clear()
      ..addAll([
        ...changeSet.incoming.map((c) => c.path),
        ...changeSet.conflicts.map((c) => c.path),
      ]);
    _previewChange = null;
  }

  void _discardSession() {
    Navigator.of(context).pop();
  }

  Future<void> _applyChanges() async {
    final server = _server;
    final peerStore = _peerStore;
    final meta = _workspaceMeta;
    final workspacePath = _workspacePath;
    if (server == null ||
        peerStore == null ||
        meta == null ||
        workspacePath == null ||
        !_session.isConnected ||
        _applying) {
      return;
    }

    if (_acceptedPaths.isEmpty && _session.changeSet.outgoing.isEmpty) {
      _discardSession();
      return;
    }

    setState(() => _applying = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(autoSaveNotifierProvider.notifier).flushNow(force: true);
      final result = await applySyncSession(
        workspaceRoot: workspacePath,
        peerStore: peerStore,
        workspaceMeta: meta,
        peer: _session.peer,
        changeSet: _session.changeSet,
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
      messenger.showSnackBar(
        getSnackBar('$kErrSyncApplyFailed: $e'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final incoming = _session.changeSet.incoming;
    final outgoing = _session.changeSet.outgoing;
    final conflicts = _session.changeSet.conflicts;
    final hasWork = _acceptedPaths.isNotEmpty || outgoing.isNotEmpty;
    final canApply = _session.isConnected && hasWork && !_applying;

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
                      onPressed: _applying ? null : _discardSession,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: kLabelClose,
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
                      child: _SyncSidePanel(
                        session: _session,
                        qrPayload: _qrPayload,
                        starting: _starting,
                        errorText: _startError,
                        scheme: scheme,
                        textTheme: textTheme,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 300,
                      child: _SyncChangesPanel(
                        isConnected: _session.isConnected,
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
                      onPressed: _applying ? null : _discardSession,
                      child: const Text(kLabelSyncDiscardSession),
                    ),
                    kHSpacer8,
                    FilledButton(
                      onPressed: canApply ? _applyChanges : null,
                      child: Text(
                        _applying
                            ? kLabelSyncApplying
                            : !canApply
                                ? kLabelSyncApplyChanges
                                : _acceptedPaths.isEmpty
                                    ? kLabelSyncApplyChanges
                                    : '$kLabelSyncApplyChanges (${_acceptedPaths.length})',
                      ),
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
}

class _SyncSidePanel extends StatelessWidget {
  const _SyncSidePanel({
    required this.session,
    required this.qrPayload,
    required this.starting,
    required this.errorText,
    required this.scheme,
    required this.textTheme,
  });

  final SyncSessionPreview session;
  final SyncQrPayload? qrPayload;
  final bool starting;
  final String? errorText;
  final ColorScheme scheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
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
              child: _buildQrArea(context),
            ),
          ),
          kVSpacer10,
          Text(
            qrPayload != null ? kLabelSyncScanQr : kLabelSyncQrPlaceholder,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (session.isConnected) ...[
            kVSpacer8,
            Text(
              session.wasPairedBefore
                  ? kLabelSyncPairedBefore
                  : kLabelSyncFirstPair,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          kVSpacer10,
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
                  session.isConnected
                      ? Icons.phone_iphone_rounded
                      : Icons.hourglass_empty_rounded,
                  size: 20,
                  color: session.isConnected
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                kHSpacer10,
                Expanded(
                  child: Text(
                    session.isConnected
                        ? kLabelSyncConnectedTo
                        : kLabelSyncWaitingForPhone,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
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

  Widget _buildQrArea(BuildContext context) {
    if (starting) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (qrPayload == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 56,
            color: scheme.error.withValues(alpha: 0.85),
          ),
          kVSpacer8,
          Text(
            errorText ?? kErrSyncServerStart,
            style: textTheme.labelMedium?.copyWith(color: scheme.error),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: QrImageView(
        data: qrPayload!.encode(),
        version: QrVersions.auto,
        gapless: true,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
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
