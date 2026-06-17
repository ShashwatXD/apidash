import 'package:apidash/git/consts.dart';
import 'package:apidash/git/widgets/git_diff_panel.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_diff_file_kind.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_diff_snapshots.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_json_fallback_column.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_visual_diff_view.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../consts.dart';
import '../models/sync_models.dart';
import '../sync_workspace_io.dart';
import '../transport/sync_file_transfer.dart';

class SyncDiffPanel extends ConsumerStatefulWidget {
  const SyncDiffPanel({
    super.key,
    required this.change,
    required this.workspaceRoot,
    required this.transfer,
  });

  final SyncFileChange? change;
  final String workspaceRoot;
  final SyncFileTransfer? transfer;

  @override
  ConsumerState<SyncDiffPanel> createState() => _SyncDiffPanelState();
}

class _LoadedDiff {
  const _LoadedDiff({
    required this.localContent,
    required this.peerContent,
  });

  final String? localContent;
  final String? peerContent;
}

class _SyncDiffPanelState extends ConsumerState<SyncDiffPanel> {
  bool _useVisualDiff = true;
  Future<_LoadedDiff>? _loadFuture;
  _LoadedDiff? _cached;
  String? _loadedPath;

  @override
  void didUpdateWidget(SyncDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.change?.path != oldWidget.change?.path) {
      _scheduleLoad();
    }
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
      });
      return;
    }
    if (change.path == _loadedPath && _cached != null) return;

    setState(() {
      _loadedPath = change.path;
      _useVisualDiff = _supportsVisualDiff(change.path);
      _loadFuture = _load(change).then((result) {
        if (mounted) setState(() => _cached = result);
        return result;
      });
    });
  }

  Future<_LoadedDiff> _load(SyncFileChange change) async {
    final transfer = widget.transfer;

    String? local;
    if (_shouldLoadLocal(change)) {
      local = await readSyncableWorkspaceFile(widget.workspaceRoot, change.path);
    }

    String? peer;
    if (_shouldLoadPeer(change) && transfer != null) {
      peer = await transfer.fetchPeerFile(change.path);
    }

    return _LoadedDiff(localContent: local, peerContent: peer);
  }

  bool _shouldLoadLocal(SyncFileChange change) {
    return switch ((change.direction, change.kind)) {
      (SyncChangeDirection.incoming, SyncFileChangeKind.added) => false,
      (SyncChangeDirection.outgoing, SyncFileChangeKind.deleted) => false,
      _ => true,
    };
  }

  bool _shouldLoadPeer(SyncFileChange change) {
    return switch ((change.direction, change.kind)) {
      (SyncChangeDirection.incoming, SyncFileChangeKind.deleted) => false,
      (SyncChangeDirection.outgoing, SyncFileChangeKind.added) => false,
      _ => true,
    };
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

    if (_loadFuture != null && _cached == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    final loaded = _cached;
    final localContent = loaded?.localContent;
    final peerContent = loaded?.peerContent;
    final fileKind = detectGitDiffFileKind(change.path);
    final supportsVisual = _supportsVisualDiff(change.path);
    final snapshots = GitDiffSnapshots(
      headRaw: localContent,
      currentRaw: peerContent,
      headJson: parseJsonMap(localContent),
      currentJson: parseJsonMap(peerContent),
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
              localContent: localContent,
              peerContent: peerContent,
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
    required String? localContent,
    required String? peerContent,
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

    final rawDiff = _buildRawDiff(localContent, peerContent);
    if (rawDiff.trim().isNotEmpty) {
      final rows = parseDiffRows(rawDiff);
      if (rows.isNotEmpty) {
        return _SyncRawDiffView(
          rows: rows,
          peerColumnLabel: change.isIncoming
              ? kLabelSyncDiffIncoming
              : kLabelSyncDiffPeer,
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
            raw: localContent,
            fieldKey: 'sync-local-${change.path}',
          ),
        ),
        kHSpacer8,
        Expanded(
          child: GitJsonFallbackColumn(
            raw: peerContent,
            fieldKey: 'sync-peer-${change.path}',
          ),
        ),
      ],
    );
  }

  String _buildRawDiff(String? local, String? peer) {
    final leftLines = _lines(local);
    final rightLines = _lines(peer);
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

class _SyncRawDiffView extends StatelessWidget {
  const _SyncRawDiffView({
    required this.rows,
    required this.peerColumnLabel,
  });

  final List<DiffRow> rows;
  final String peerColumnLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var oldLineNum = 0;
    var newLineNum = 0;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      kLabelSyncDiffLocal,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      peerColumnLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  int? oldNum;
                  int? newNum;
                  if (row.oldLine != null) {
                    oldLineNum++;
                    oldNum = oldLineNum;
                  }
                  if (row.newLine != null) {
                    newLineNum++;
                    newNum = newLineNum;
                  }
                  return _SyncDiffRow(
                    row: row,
                    oldLineNum: oldNum,
                    newLineNum: newNum,
                    scheme: scheme,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncDiffRow extends StatelessWidget {
  const _SyncDiffRow({
    required this.row,
    required this.oldLineNum,
    required this.newLineNum,
    required this.scheme,
  });

  final DiffRow row;
  final int? oldLineNum;
  final int? newLineNum;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _SyncDiffCell(
              lineNumber: oldLineNum,
              text: row.oldLine,
              isRemoved: row.isDeletion,
              scheme: scheme,
            ),
          ),
          Container(
            width: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
          Expanded(
            child: _SyncDiffCell(
              lineNumber: newLineNum,
              text: row.newLine,
              isAdded: row.isAddition,
              scheme: scheme,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncDiffCell extends StatelessWidget {
  const _SyncDiffCell({
    required this.lineNumber,
    required this.text,
    required this.scheme,
    this.isAdded = false,
    this.isRemoved = false,
  });

  final int? lineNumber;
  final String? text;
  final ColorScheme scheme;
  final bool isAdded;
  final bool isRemoved;

  @override
  Widget build(BuildContext context) {
    Color? bg;
    if (isAdded) {
      bg = scheme.tertiaryContainer.withValues(alpha: 0.45);
    } else if (isRemoved) {
      bg = scheme.errorContainer.withValues(alpha: 0.35);
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: lineNumber != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 6, top: 2),
                    child: Text(
                      '$lineNumber',
                      textAlign: TextAlign.right,
                      style: kCodeStyle.copyWith(
                        fontSize: 11,
                        height: 1.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: SelectableText(
              text ?? '',
              style: kCodeStyle.copyWith(
                fontSize: 12,
                height: 1.5,
                color: scheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
