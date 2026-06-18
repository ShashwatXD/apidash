import 'dart:async';

import 'package:apidash/git/models/git_change_tree.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/widgets/git_changes_tree.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/models/sync_models.dart';
import 'package:apidash/sync/providers/sync_providers.dart';
import 'package:apidash/sync/storage/peer_sync_store.dart';
import 'package:apidash/sync/storage/sync_device_store.dart';
import 'package:apidash/sync/sync_apply.dart';
import 'package:apidash/sync/sync_change_adapter.dart';
import 'package:apidash/sync/sync_manifest_builder.dart';
import 'package:apidash/sync/sync_workspace_path.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
import 'package:apidash/sync/transport/sync_session_client.dart';
import 'package:apidash/sync/ui/sync_diff_panel.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Post-scan sync session on mobile — review changes and apply.
class SyncSessionPage extends ConsumerStatefulWidget {
  const SyncSessionPage({super.key, required this.qrPayload});

  final SyncQrPayload qrPayload;

  @override
  ConsumerState<SyncSessionPage> createState() => _SyncSessionPageState();
}

class _SyncSessionPageState extends ConsumerState<SyncSessionPage> {
  static const _emptySession = SyncSessionPreview(
    peer: SyncPeerInfo(deviceId: '', displayName: '', syncWorkspaceId: ''),
    changeSet: SyncChangeSet(),
    isConnected: false,
    wasPairedBefore: false,
  );

  SyncSessionPreview _session = _emptySession;
  final Set<String> _acceptedPaths = {};
  SyncFileChange? _previewChange;
  Map<String, SyncFileChange> _changesByPath = {};

  SyncSessionClient? _client;
  PeerSyncStore? _peerStore;
  String? _workspacePath;
  bool _connecting = true;
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resetChangeSelection(const SyncChangeSet());
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
      final peerStore = PeerSyncStore(workspacePath);
      final identity = await SyncDeviceStore(workspacePath).getOrCreate();
      final meta = await peerStore.getOrCreateMeta();
      final manifest = await buildSyncManifest(workspacePath);

      final client = SyncSessionClient(
        identity: identity,
        workspaceMeta: meta,
        localManifest: manifest,
        peerStore: peerStore,
        workspaceRoot: workspacePath,
        qrPayload: widget.qrPayload,
      )
        ..onHostConnected = _handleHostConnected
        ..onHostDisconnected = _handleHostDisconnected
        ..onChangeSet = _handleChangeSet
        ..onError = _handleError
        ..onRemoteApplied = _handleRemoteApplied;

      await client.connect();
      if (!mounted) {
        await client.disconnect();
        return;
      }
      setState(() {
        _client = client;
        _peerStore = peerStore;
        _workspacePath = workspacePath;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = '$kErrSyncConnectFailed ($e)';
      });
    }
  }

  void _handleHostConnected(SyncPeerInfo host, bool wasPairedBefore) {
    if (!mounted) return;
    setState(() {
      _session = SyncSessionPreview(
        peer: host,
        changeSet: _session.changeSet,
        isConnected: true,
        wasPairedBefore: wasPairedBefore,
      );
    });
  }

  void _handleHostDisconnected() {
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

  void _handleError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  Future<void> _handleRemoteApplied() async {
    if (!mounted) return;
    await reloadWorkspaceFromDisk(ref);
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

  void _showDiffModal(GitChange change) {
    final preview = _changesByPath[change.path];
    if (preview == null) return;

    final workspacePath = _workspacePath;
    if (workspacePath == null) return;

    setState(() => _previewChange = preview);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.88;
        return SizedBox(
          height: sheetHeight,
          child: SyncDiffPanel(
            change: preview,
            workspaceRoot: workspacePath,
            transfer: _client,
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _previewChange = null);
    });
  }

  Future<void> _apply() async {
    final client = _client;
    final peerStore = _peerStore;
    final workspacePath = _workspacePath;
    if (client == null ||
        peerStore == null ||
        workspacePath == null ||
        !_session.isConnected ||
        _applying) {
      return;
    }

    final outgoing = _session.changeSet.outgoing;
    if (_acceptedPaths.isEmpty && outgoing.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _applying = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await ref.read(autoSaveNotifierProvider.notifier).flushNow(force: true);
      final localMeta = await peerStore.getOrCreateMeta();
      final result = await applySyncSession(
        workspaceRoot: workspacePath,
        peerStore: peerStore,
        workspaceMeta: SyncWorkspaceMeta(
          syncWorkspaceId: _session.peer.syncWorkspaceId,
          displayName: localMeta.displayName,
        ),
        peer: _session.peer,
        changeSet: _session.changeSet,
        acceptedPaths: _acceptedPaths,
        transfer: client,
        peerManifest: client.peerManifest,
      );
      await reloadWorkspaceFromDisk(ref);
      await invalidateSyncUnsyncedCount(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        getSnackBar(
          '$kMsgSyncApplySuccess '
          '(${result.appliedIncoming} from desktop, ${result.sentOutgoing} to desktop)',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      messenger.showSnackBar(getSnackBar('$kErrSyncApplyFailed: $e'));
    }
  }

  Future<void> _leaveSession() async {
    if (_applying) return;
    await _client?.disconnect();
    if (!mounted) return;
    Navigator.of(context).pop();
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

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        leading: BackButton(
          onPressed: _applying ? null : _leaveSession,
        ),
        title: Text(
          _session.isConnected
              ? '$kLabelSyncConnectedTo ${_session.peer.displayName}'
              : kLabelSyncConnecting,
        ),
        actions: [
          if (_applying)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(scheme, textTheme, incoming, conflicts),
      bottomNavigationBar: _connecting || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _applying ? null : _leaveSession,
                      child: const Text(kLabelSyncDiscardSession),
                    ),
                    kHSpacer8,
                    FilledButton(
                      onPressed: canApply ? _apply : null,
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
            ),
    );
  }

  Widget _buildBody(
    ColorScheme scheme,
    TextTheme textTheme,
    List<SyncFileChange> incoming,
    List<SyncFileChange> conflicts,
  ) {
    if (_connecting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: kP20,
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: scheme.error),
          ),
        ),
      );
    }

    if (!_session.isConnected) {
      return Center(
        child: Text(
          kLabelSyncConnecting,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final reviewable = [...incoming, ...conflicts];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            _session.wasPairedBefore
                ? kLabelSyncPairedBefore
                : kLabelSyncFirstPair,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (reviewable.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              kLabelSyncFromDesktop,
              style: textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (reviewable.isNotEmpty)
          Expanded(
            child: GitChangesTree(
              roots: buildGitChangeTree(syncChangesToGitChanges(reviewable)),
              selectedPaths: _acceptedPaths,
              previewPath: _previewChange?.path,
              busy: false,
              onSelectionChanged: (paths) {
                setState(() {
                  _acceptedPaths
                    ..clear()
                    ..addAll(paths);
                });
              },
              onFilePreview: _showDiffModal,
            ),
          ),
        if (reviewable.isEmpty)
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
