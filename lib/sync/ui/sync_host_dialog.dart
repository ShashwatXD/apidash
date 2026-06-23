import 'dart:async';

import 'package:apidash/git/providers/providers.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/sync/widgets/sync_direction_panel.dart';
import 'package:apidash/sync/widgets/sync_diff_panel.dart';
import 'package:apidash/sync/widgets/sync_info_banner.dart';
import 'package:apidash/sync/widgets/sync_panel.dart';
import 'package:apidash/sync/widgets/sync_qr_panel.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  WorkspaceIdentity? _workspace;
  SyncChangeSet _changeSet = const SyncChangeSet();
  SyncDirectionMode _directionMode = SyncDirectionMode.send;
  SyncFileChange? _previewChange;
  Map<String, SyncFileChange> _changesByPath = {};

  SyncSessionServer? _server;
  SyncStorage? _storage;
  String? _workspacePath;
  SyncQrPayload? _qrPayload;
  bool _starting = true;
  bool _connected = false;
  bool _wasPairedBefore = false;
  bool _updating = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    _rebuildChangesByPath(const SyncChangeSet());
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
      server.onPeerConnected = (peer, wasPaired) => setState(() {
        _peer = peer;
        _connected = true;
        _wasPairedBefore = wasPaired;
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
        _workspace = workspace;
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
      _directionMode = defaultDirectionMode(changeSet);
      _rebuildChangesByPath(changeSet);
    });
  }

  void _rebuildChangesByPath(SyncChangeSet changeSet) {
    _changesByPath = syncChangesByPath([
      ...changeSet.incoming,
      ...changeSet.outgoing,
    ]);
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
    ScaffoldMessenger.of(context)
        .showSnackBar(getSnackBar(kMsgSyncWorkspaceUpdated));
  }

  Future<bool> _confirmReceiveIfNeeded() async {
    final overlap = overlappingForDirection(_changeSet, SyncDirectionMode.receive);
    if (overlap.isEmpty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(kLabelSyncReceiveConfirmTitle),
        content: Text(
          overlapWarningMessage(
                mode: SyncDirectionMode.receive,
                overlapping: overlap,
                isHost: true,
              ) ??
              kLabelSyncReceiveConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(kLabelSyncDiscardSession),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(kLabelSyncUpdate),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _update() async {
    final server = _server;
    final storage = _storage;
    final workspacePath = _workspacePath;
    if (server == null ||
        storage == null ||
        workspacePath == null ||
        !_connected ||
        _updating) {
      return;
    }

    final changes = changesForDirection(_changeSet, _directionMode);
    if (changes.isEmpty) return;

    if (_directionMode == SyncDirectionMode.receive) {
      final confirmed = await _confirmReceiveIfNeeded();
      if (!confirmed || !mounted) return;
    }

    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(autoSaveNotifierProvider.notifier).flushNow(force: true);

      final SyncApplyResult result;
      if (_directionMode == SyncDirectionMode.send) {
        result = await applySend(
          workspaceRoot: workspacePath,
          storage: storage,
          peer: _peer,
          outgoing: changes,
          transfer: server,
          peerManifest: server.peerManifest,
        );
      } else {
        result = await applyReceive(
          workspaceRoot: workspacePath,
          storage: storage,
          peer: _peer,
          incoming: changes,
          transfer: server,
          peerManifest: server.peerManifest,
        );
      }

      await server.refreshManifest();
      await reloadWorkspaceFromDisk(ref);
      await refreshGitStatus(ref);
      await invalidateSyncUnsyncedCount(ref);
      if (!mounted) return;
      setState(() => _updating = false);
      messenger.showSnackBar(
        getSnackBar(
          _directionMode == SyncDirectionMode.send
              ? '$kMsgSyncUpdateSuccess (${result.sentOutgoing} to phone)'
              : '$kMsgSyncUpdateSuccess (${result.appliedIncoming} from phone)',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _updating = false);
      messenger.showSnackBar(getSnackBar('$kErrSyncUpdateFailed: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final activeChanges = changesForDirection(_changeSet, _directionMode);
    final canUpdate = _connected && activeChanges.isNotEmpty && !_updating;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 720),
        child: SizedBox(
          width: 1040,
          height: 660,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kLabelSyncToPhone,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_workspace != null) ...[
                            kVSpacer5,
                            Text(
                              _workspace!.name,
                              style: textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_updating)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    IconButton(
                      onPressed: _updating ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: kLabelSyncClose,
                    ),
                  ],
                ),
              ),
              if (_startError != null && _qrPayload == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SyncInfoBanner(
                    message: _startError!,
                    isError: true,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 272,
                        child: SyncPanel(
                          child: SyncQrPanel(
                            starting: _starting,
                            qrPayload: _qrPayload,
                            startError: _startError,
                            connected: _connected,
                            peerDisplayName: _peer.displayName,
                            wasPairedBefore: _wasPairedBefore,
                          ),
                        ),
                      ),
                      kHSpacer10,
                      SizedBox(
                        width: 300,
                        child: SyncPanel(
                          child: SyncDirectionPanel(
                            isConnected: _connected,
                            isHost: true,
                            changeSet: _changeSet,
                            directionMode: _directionMode,
                            previewPath: _previewChange?.path,
                            onDirectionModeChanged: (mode) {
                              setState(() => _directionMode = mode);
                            },
                            onFilePreview: (change) {
                              setState(() {
                                _previewChange = _changesByPath[change.path];
                              });
                            },
                          ),
                        ),
                      ),
                      kHSpacer10,
                      Expanded(
                        child: SyncPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_previewChange != null)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                    onPressed: _updating
                                        ? null
                                        : () => setState(
                                              () => _previewChange = null,
                                            ),
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      size: 20,
                                    ),
                                    tooltip: kLabelSyncSelectFile,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              Expanded(
                                child: SyncDiffPanel(
                                  change: _previewChange,
                                  workspaceRoot: _workspacePath ?? '',
                                  storage: _storage,
                                  localManifest:
                                      _server?.localManifest ?? const {},
                                  peerManifest:
                                      _server?.peerManifest ?? const {},
                                  transfer: _server,
                                  directionMode: _directionMode,
                                  isHost: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: _updating ? null : () => Navigator.pop(context),
                      child: const Text(kLabelSyncDiscardSession),
                    ),
                    kHSpacer8,
                    FilledButton(
                      onPressed: canUpdate ? _update : null,
                      child: Text(
                        updateButtonLabel(
                          mode: _directionMode,
                          isHost: true,
                          count: activeChanges.length,
                          updating: _updating,
                        ),
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
