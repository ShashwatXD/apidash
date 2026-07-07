import 'package:apidash/git/consts.dart';
import 'package:apidash/git/widgets/git_raw_diff_view.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_diff_file_kind.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_diff_snapshots.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_json_fallback_column.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_visual_diff_view.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../consts.dart';
import '../models/sync_models.dart';
import '../storage/sync_storage.dart';
import '../sync_workspace_io.dart';
import '../transport/sync_file_transfer.dart';

class SyncDiffPanel extends ConsumerStatefulWidget {
  const SyncDiffPanel({
    super.key,
    required this.change,
    required this.workspaceRoot,
    this.storage,
    required this.localManifest,
    required this.peerManifest,
    required this.transfer,
    required this.directionMode,
    this.isHost = false,
  });

  final SyncFileChange? change;
  final String workspaceRoot;
  final SyncStorage? storage;
  final Map<String, String> localManifest;
  final Map<String, String> peerManifest;
  final SyncFileTransfer? transfer;
  final SyncDirectionMode directionMode;
  final bool isHost;

  @override
  ConsumerState<SyncDiffPanel> createState() => _SyncDiffPanelState();
}

class _LoadedDiff {
  const _LoadedDiff({
    required this.baselineContent,
    required this.currentContent,
  });

  final String? baselineContent;
  final String? currentContent;
}

class _SyncDiffPanelState extends ConsumerState<SyncDiffPanel> {
  bool _useVisualDiff = true;
  Future<_LoadedDiff>? _loadFuture;
  _LoadedDiff? _cached;
  String? _loadedPath;
  SyncDirectionMode? _loadedMode;

  @override
  void didUpdateWidget(SyncDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.change?.path != oldWidget.change?.path ||
        widget.directionMode != oldWidget.directionMode ||
        widget.storage != oldWidget.storage) {
      _scheduleLoad();
    }
  }

  String get _currentColumnLabel {
    return switch (widget.directionMode) {
      SyncDirectionMode.send => kLabelSyncDiffLocal,
      SyncDirectionMode.receive =>
        widget.isHost ? kLabelSyncDiffPeerPhone : kLabelSyncDiffPeerComputer,
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleLoad();
    });
  }

  void _scheduleLoad() {
    final change = widget.change;
    if (change == null) {
      setState(() {
        _loadFuture = null;
        _cached = null;
        _loadedPath = null;
        _loadedMode = null;
      });
      return;
    }
    if (widget.storage == null) {
      setState(() {
        _loadFuture = null;
        _cached = null;
        _loadedPath = change.path;
        _loadedMode = widget.directionMode;
      });
      return;
    }
    if (change.path == _loadedPath &&
        _loadedMode == widget.directionMode &&
        _cached != null) {
      return;
    }

    setState(() {
      _loadedPath = change.path;
      _loadedMode = widget.directionMode;
      _useVisualDiff = _supportsVisualDiff(change.path);
      _loadFuture = _load(change).then((result) {
        if (mounted) setState(() => _cached = result);
        return result;
      });
    });
  }

  Future<_LoadedDiff> _load(SyncFileChange change) async {
    final storage = widget.storage;
    if (storage == null) {
      return const _LoadedDiff(
        baselineContent: null,
        currentContent: null,
      );
    }
    final transfer = widget.transfer;
    final state = await storage.readSyncState();
    final baseline = state?.baseline ?? const <String, String>{};
    final baselineHash = baseline[change.path];
    final localHash = widget.localManifest[change.path];
    final peerHash = widget.peerManifest[change.path];

    String? local;
    if (_shouldLoadLocal(change)) {
      local = await readSyncableWorkspaceFile(widget.workspaceRoot, change.path);
    }

    String? peer;
    if (_shouldLoadPeer(change) && transfer != null) {
      peer = await transfer.fetchPeerFile(change.path);
    }

    final baselineContent = _resolveBaselineContent(
      baselineHash: baselineHash,
      localHash: localHash,
      peerHash: peerHash,
      localContent: local,
      peerContent: peer,
      kind: change.kind,
    );

    final currentContent = switch (widget.directionMode) {
      SyncDirectionMode.send => local,
      SyncDirectionMode.receive => peer,
    };

    return _LoadedDiff(
      baselineContent: baselineContent,
      currentContent: currentContent,
    );
  }

  String? _resolveBaselineContent({
    required String? baselineHash,
    required String? localHash,
    required String? peerHash,
    required String? localContent,
    required String? peerContent,
    required SyncFileChangeKind kind,
  }) {
    if (kind == SyncFileChangeKind.added || baselineHash == null) {
      return null;
    }
    if (localHash == baselineHash) return localContent;
    if (peerHash == baselineHash) return peerContent;
    return null;
  }

  bool _shouldLoadLocal(SyncFileChange change) {
    if (change.kind == SyncFileChangeKind.deleted &&
        widget.directionMode == SyncDirectionMode.send) {
      return false;
    }
    return true;
  }

  bool _shouldLoadPeer(SyncFileChange change) {
    if (change.kind == SyncFileChangeKind.deleted &&
        widget.directionMode == SyncDirectionMode.receive) {
      return false;
    }
    return true;
  }

  bool _supportsVisualDiff(String path) {
    if (detectGitDiffFileKind(path) == GitDiffFileKind.response) {
      return false;
    }
    return gitDiffSupportsVisual(path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final change = widget.change;

    if (change == null) {
      return Center(
        child: Padding(
          padding: kP20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 40,
                color: scheme.outline.withValues(alpha: 0.7),
              ),
              kVSpacer10,
              Text(
                kLabelSyncSelectFile,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.storage == null ||
        (_loadFuture != null && _cached == null)) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    final loaded = _cached;
    final baselineContent = loaded?.baselineContent;
    final currentContent = loaded?.currentContent;
    final fileKind = detectGitDiffFileKind(change.path);
    final supportsVisual = _supportsVisualDiff(change.path);
    final snapshots = GitDiffSnapshots(
      headRaw: baselineContent,
      currentRaw: currentContent,
      headJson: parseJsonMap(baselineContent),
      currentJson: parseJsonMap(currentContent),
    );
    final fileName = change.path.split('/').last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                change.path,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
              kVSpacer8,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (supportsVisual) ...[
                    kHSpacer8,
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text(kLabelGitDiffVisual),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(kLabelGitDiffRaw),
                        ),
                      ],
                      selected: {_useVisualDiff},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        setState(() => _useVisualDiff = selection.first);
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildDiffBody(
              change: change,
              baselineContent: baselineContent,
              currentContent: currentContent,
              fileKind: fileKind,
              snapshots: snapshots,
              supportsVisual: supportsVisual,
              scheme: scheme,
              textTheme: textTheme,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiffBody({
    required SyncFileChange change,
    required String? baselineContent,
    required String? currentContent,
    required GitDiffFileKind fileKind,
    required GitDiffSnapshots snapshots,
    required bool supportsVisual,
    required ColorScheme scheme,
    required TextTheme textTheme,
  }) {
    if (supportsVisual && _useVisualDiff) {
      return GitVisualDiffView(
        fileKind: fileKind,
        snapshots: snapshots,
      );
    }

    final rawDiff = _buildRawDiff(baselineContent, currentContent);
    if (rawDiff.trim().isNotEmpty) {
      final rows = parseGitRawDiffRows(rawDiff);
      if (rows.isNotEmpty) {
        return GitRawDiffView(
          rows: rows,
          leftColumnLabel: kLabelSyncDiffBaseline,
          rightColumnLabel: _currentColumnLabel,
        );
      }
    }

    if (!snapshots.hasContent) {
      return Center(
        child: Text(
          kLabelGitDiffEmpty,
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GitJsonFallbackColumn(
            raw: baselineContent,
            fieldKey: 'sync-baseline-${change.path}',
          ),
        ),
        kHSpacer8,
        Expanded(
          child: GitJsonFallbackColumn(
            raw: currentContent,
            fieldKey: 'sync-current-${change.path}',
          ),
        ),
      ],
    );
  }

  String _buildRawDiff(String? baseline, String? current) {
    final leftLines = _lines(baseline);
    final rightLines = _lines(current);
    final rows = <String>[];

    final maxLen = leftLines.length > rightLines.length
        ? leftLines.length
        : rightLines.length;
    for (var i = 0; i < maxLen; i++) {
      final left = i < leftLines.length ? leftLines[i] : null;
      final right = i < rightLines.length ? rightLines[i] : null;
      if (left == right) {
        if (left != null) rows.add(' $left');
      } else {
        if (left != null) rows.add('-$left');
        if (right != null) rows.add('+$right');
      }
    }
    return rows.join('\n');
  }

  List<String> _lines(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return prettyJson(raw).split('\n');
  }
}
