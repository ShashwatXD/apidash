import 'dart:async';

import 'package:apidash/git/models/git_change_tree.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/widgets/git_changes_tree.dart';
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
import 'package:apidash/sync/sync_workspace_path.dart';
import 'package:apidash/sync/transport/sync_messages.dart';
import 'package:apidash/sync/transport/sync_session_client.dart';
import 'package:apidash/sync/widgets/sync_diff_panel.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
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
  final Set<String> _acceptedPaths = {};
  SyncFileChange? _previewChange;
  Map<String, SyncFileChange> _changesByPath = {};

  SyncSessionClient? _client;
  SyncStorage? _storage;
  String? _workspacePath;
  bool _connecting = true;
  bool _connected = false;
  bool _wasPairedBefore = false;
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
      client.onPeerDisconnected = () => setState(() => _connected = false);
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = kErrSyncConnectFailed;
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

  Future<void> _handleRemoteApplied() async {
    await reloadWorkspaceFromDisk(ref);
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
    final messenger = ScaffoldMessenger.of(context);
    SyncApplyResult? result;

    try {
      await ref.read(autoSaveNotifierProvider.notifier).flushNow(force: true);

      if (widget.mode == SyncSessionMode.workspaceReplace) {
        await applyReplaceFromPeer(
          workspaceRoot: workspacePath,
          storage: storage,
          peer: _peer,
          transfer: client,
          peerManifest: client.peerManifest,
        );
        await storage.writeWorkspace(
          WorkspaceIdentity(
            id: widget.qrPayload.workspaceId,
            name: widget.qrPayload.workspaceName,
          ),
        );
      } else {
        if (!sessionHasWork(_changeSet, _acceptedPaths)) {
          if (mounted) Navigator.of(context).pop();
          return;
        }
        result = await applySyncSession(
          workspaceRoot: workspacePath,
          storage: storage,
          peer: _peer,
          changeSet: _changeSet,
          acceptedPaths: _acceptedPaths,
          transfer: client,
          peerManifest: client.peerManifest,
        );
      }

      await reloadWorkspaceFromDisk(ref);
      await invalidateSyncUnsyncedCount(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (result == null) {
        messenger.showSnackBar(getSnackBar(kMsgSyncApplySuccess));
      } else {
        messenger.showSnackBar(
          getSnackBar(
            '$kMsgSyncApplySuccess '
            '(${result.appliedIncoming} from desktop, ${result.sentOutgoing} to desktop)',
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      messenger.showSnackBar(getSnackBar('$kErrSyncApplyFailed: $e'));
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
          transfer: _client,
          isHost: false,
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _previewChange = null);
    });
  }

  String _applyButtonLabel(bool isReplaceMode, bool canApply) {
    if (_applying) return kLabelSyncApplying;
    if (isReplaceMode) {
      return applyButtonLabel(mode: widget.mode, hasWork: canApply);
    }
    if (!canApply || _acceptedPaths.isEmpty) return kLabelSyncApplyChanges;
    return '$kLabelSyncApplyChanges (${_acceptedPaths.length})';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isReplaceMode = widget.mode == SyncSessionMode.workspaceReplace;
    final hasWork =
        isReplaceMode ? _changeSet.incoming.isNotEmpty || _connected : sessionHasWork(_changeSet, _acceptedPaths);
    final canApply = _connected && hasWork && !_applying && _error == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _connected
              ? '${kLabelSyncConnectedTo} ${_peer.displayName}'
              : kLabelSyncConnecting,
        ),
      ),
      body: _buildBody(scheme, textTheme, isReplaceMode),
      bottomNavigationBar: _connecting || _error != null
          ? null
          : SafeArea(
              child: Padding(
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
                      child: Text(_applyButtonLabel(isReplaceMode, hasWork)),
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: scheme.error)),
      );
    }
    if (!_connected) {
      return Center(child: Text(kLabelSyncConnecting));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            _hintForMode(),
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: isReplaceMode
              ? _buildReplaceSummary(textTheme, scheme)
              : _buildReviewList(textTheme, scheme),
        ),
      ],
    );
  }

  Widget _buildReviewList(TextTheme textTheme, ColorScheme scheme) {
    final incoming = _changeSet.incoming;
    final conflicts = _changeSet.conflicts;
    final reviewable = [...incoming, ...conflicts];

    if (reviewable.isEmpty) {
      return Center(
        child: Text(
          kLabelSyncNoChanges,
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            onFilePreview: _showDiff,
          ),
        ),
      ],
    );
  }

  String _hintForMode() {
    return switch (widget.mode) {
      SyncSessionMode.workspaceReplace => kLabelSyncAdoptWorkspaceBody,
      SyncSessionMode.incremental =>
        _wasPairedBefore ? kLabelSyncPairedBefore : kLabelSyncFirstPair,
      _ => kLabelSyncFirstPair,
    };
  }

  Widget _buildReplaceSummary(TextTheme textTheme, ColorScheme scheme) {
    final count = _changeSet.incoming.length + _changeSet.conflicts.length;
    return Center(
      child: Padding(
        padding: kP20,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.qrPayload.workspaceName,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            kVSpacer8,
            Text(
              '$count files from ${widget.qrPayload.desktopName}',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
