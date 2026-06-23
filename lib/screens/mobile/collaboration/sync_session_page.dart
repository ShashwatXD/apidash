import 'dart:async';

import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/models/sync_models.dart';
import 'package:apidash/sync/providers/sync_providers.dart';
import 'package:apidash/sync/storage/sync_storage.dart';
import 'package:apidash/sync/sync_apply.dart';
import 'package:apidash/sync/sync_change_adapter.dart';
import 'package:apidash/sync/sync_display_name.dart';
import 'package:apidash/sync/sync_manifest_builder.dart';
import 'package:apidash/sync/sync_session_compute.dart';
import 'package:apidash/sync/sync_scan.dart';
import 'package:apidash/sync/sync_workspace_path.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
import 'package:apidash/sync/transport/sync_session_client.dart';
import 'package:apidash/sync/widgets/sync_connection_status_card.dart';
import 'package:apidash/sync/widgets/sync_diff_panel.dart';
import 'package:apidash/sync/widgets/sync_direction_panel.dart';
import 'package:apidash/sync/widgets/sync_info_banner.dart';
import 'package:apidash/sync/widgets/sync_replace_summary_panel.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncSessionPage extends ConsumerStatefulWidget {
  const SyncSessionPage({
    super.key,
    required this.qrPayload,
    required this.mode,
  });

  final SyncQrPayload qrPayload;
  final SyncSessionMode mode;

  @override
  ConsumerState<SyncSessionPage> createState() => _SyncSessionPageState();
}

class _SyncSessionPageState extends ConsumerState<SyncSessionPage> {
  static final _emptyPeer = SyncPeerInfo(
    workspaceId: '',
    workspaceName: '',
    displayName: '',
  );

  SyncPeerInfo _peer = _emptyPeer;
  SyncChangeSet _changeSet = const SyncChangeSet();
  SyncDirectionMode _directionMode = SyncDirectionMode.send;
  SyncFileChange? _previewChange;
  Map<String, SyncFileChange> _changesByPath = {};

  SyncSessionClient? _client;
  SyncStorage? _storage;
  String? _workspacePath;
  bool _connecting = true;
  bool _connected = false;
  bool _wasPairedBefore = false;
  bool _updating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rebuildChangesByPath(const SyncChangeSet());
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
        sessionMode: widget.mode,
      );
      client.onPeerConnected = (peer, wasPaired) => setState(() {
        _peer = peer;
        _connected = true;
        _wasPairedBefore = wasPaired;
      });
      client.onPeerDisconnected = _handlePeerDisconnected;
      client.onChangeSet = _handleChangeSet;
      client.onError = (msg) => setState(() => _error = msg);
      client.onRemoteApplied = _handleRemoteApplied;

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
      debugPrint('SyncSessionPage._connect failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = '$kErrSyncConnectFailed ($e)';
      });
    }
  }

  void _handlePeerDisconnected() {
    if (!mounted || _updating || !_connected) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _updating) return;
      _exitAfterPeerLeft();
    });
  }

  void _exitAfterPeerLeft() {
    final navigator = Navigator.of(context);
    if (_previewChange != null && navigator.canPop()) {
      navigator.pop();
    }
    if (!mounted) return;
    if (navigator.canPop()) {
      navigator.pop();
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

  Future<void> _handleRemoteApplied() async {
    await reloadWorkspaceFromDisk(ref);
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
                isHost: false,
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
    final client = _client;
    final storage = _storage;
    final workspacePath = _workspacePath;
    if (client == null ||
        storage == null ||
        workspacePath == null ||
        !_connected ||
        _updating) {
      return;
    }

    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.of(context);
    var updatedCount = 0;

    try {
      await ref.read(autoSaveNotifierProvider.notifier).flushNow(force: true);

      if (widget.mode == SyncSessionMode.workspaceReplace) {
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
      } else {
        final changes = changesForDirection(_changeSet, _directionMode);
        if (changes.isEmpty) {
          setState(() => _updating = false);
          return;
        }
        updatedCount = changes.length;

        if (_directionMode == SyncDirectionMode.receive) {
          final confirmed = await _confirmReceiveIfNeeded();
          if (!confirmed || !mounted) {
            setState(() => _updating = false);
            return;
          }
        }

        if (_directionMode == SyncDirectionMode.send) {
          await applySend(
            workspaceRoot: workspacePath,
            storage: storage,
            peer: _peer,
            outgoing: changes,
            transfer: client,
            peerManifest: client.peerManifest,
          );
        } else {
          await applyReceive(
            workspaceRoot: workspacePath,
            storage: storage,
            peer: _peer,
            incoming: changes,
            transfer: client,
            peerManifest: client.peerManifest,
          );
        }
        await client.refreshManifest();
      }

      await reloadWorkspaceFromDisk(ref);
      await invalidateSyncUnsyncedCount(ref);
      if (!mounted) return;

      if (widget.mode == SyncSessionMode.workspaceReplace) {
        Navigator.of(context).pop();
        messenger.showSnackBar(getSnackBar(kMsgSyncUpdateSuccess));
      } else {
        setState(() => _updating = false);
        messenger.showSnackBar(
          getSnackBar(
            _directionMode == SyncDirectionMode.send
                ? '$kMsgSyncUpdateSuccess ($updatedCount to computer)'
                : '$kMsgSyncUpdateSuccess ($updatedCount from computer)',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _updating = false);
      messenger.showSnackBar(getSnackBar('$kErrSyncUpdateFailed: $e'));
    }
  }

  void _showDiff(GitChange change) {
    final preview = _changesByPath[change.path];
    if (preview == null || _workspacePath == null) return;
    setState(() => _previewChange = preview);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.88,
        child: SyncDiffPanel(
          change: preview,
          workspaceRoot: _workspacePath!,
          storage: _storage,
          localManifest: _client?.localManifest ?? const {},
          peerManifest: _client?.peerManifest ?? const {},
          transfer: _client,
          directionMode: _directionMode,
          isHost: false,
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _previewChange = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isReplaceMode = widget.mode == SyncSessionMode.workspaceReplace;
    final activeChanges = isReplaceMode
        ? <SyncFileChange>[]
        : changesForDirection(_changeSet, _directionMode);
    final canUpdate = isReplaceMode
        ? _connected && (_changeSet.incoming.isNotEmpty || _connected)
        : _connected && activeChanges.isNotEmpty && !_updating && _error == null;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainerLowest,
        title: Text(
          _connected ? kLabelSyncConnectedTo : kLabelSyncConnecting,
        ),
        scrolledUnderElevation: 0,
      ),
      body: _buildBody(scheme, textTheme, isReplaceMode),
      bottomNavigationBar: _connecting || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: canUpdate && !_updating ? _update : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          isReplaceMode
                              ? applyButtonLabel(
                                  mode: widget.mode,
                                  hasWork: canUpdate,
                                )
                              : updateButtonLabel(
                                  mode: _directionMode,
                                  isHost: false,
                                  count: activeChanges.length,
                                  updating: _updating,
                                ),
                        ),
                      ),
                    ),
                    kVSpacer8,
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _updating ? null : () => Navigator.pop(context),
                        child: const Text(kLabelSyncDiscardSession),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody(
    ColorScheme scheme,
    TextTheme textTheme,
    bool isReplaceMode,
  ) {
    if (_connecting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            kVSpacer16,
            Text(
              kLabelSyncConnecting,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            kVSpacer6,
            Text(
              widget.qrPayload.desktopName,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: kP20,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SyncInfoBanner(message: _error!, isError: true),
            kVSpacer16,
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(kLabelSyncClose),
            ),
          ],
        ),
      );
    }
    if (!_connected) {
      return Center(
        child: Text(
          kLabelSyncConnecting,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SyncConnectionStatusCard(
            connected: _connected,
            peerDisplayName: _peer.displayName,
            wasPairedBefore: _wasPairedBefore,
            peerIcon: Icons.computer_rounded,
            waitingIcon: Icons.sync_rounded,
            waitingLabel: kLabelSyncConnecting,
            connectedFallbackLabel: widget.qrPayload.desktopName,
          ),
        ),
        Expanded(
          child: isReplaceMode
              ? SyncReplaceSummaryPanel(
                  workspaceName: widget.qrPayload.workspaceName,
                  desktopName: widget.qrPayload.desktopName,
                  fileCount: _changeSet.incoming.length,
                )
              : SyncDirectionPanel(
                  isConnected: _connected,
                  isHost: false,
                  changeSet: _changeSet,
                  directionMode: _directionMode,
                  previewPath: _previewChange?.path,
                  onDirectionModeChanged: (mode) {
                    setState(() => _directionMode = mode);
                  },
                  onFilePreview: _showDiff,
                ),
        ),
      ],
    );
  }
}
