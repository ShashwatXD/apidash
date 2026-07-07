import 'package:apidash/git/consts.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/widgets/git_diff_display.dart';
import 'package:apidash/git/widgets/git_raw_diff_view.dart';
import 'package:apidash/git/providers/git_status_provider.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_diff_file_kind.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_diff_snapshots.dart';
import 'package:apidash/git/widgets/git_visual_diff/git_visual_diff_view.dart';
import 'package:apidash/providers/settings_providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GitDiffPanel extends ConsumerStatefulWidget {
  const GitDiffPanel({super.key, required this.change, this.refreshToken = 0});

  final GitChange? change;
  final int refreshToken;

  @override
  ConsumerState<GitDiffPanel> createState() => _GitDiffPanelState();
}

class _DiffLoadResult {
  const _DiffLoadResult({
    required this.diff,
    required this.title,
    required this.fileKind,
    required this.snapshots,
  });

  final String diff;
  final String title;
  final GitDiffFileKind fileKind;
  final GitDiffSnapshots snapshots;
}

class _GitDiffPanelState extends ConsumerState<GitDiffPanel> {
  Future<_DiffLoadResult>? _diffFuture;
  _DiffLoadResult? _cachedResult;
  String? _diffPath;
  GitChangeType? _diffType;
  int _refreshToken = -1;
  int _diskRevision = -1;
  bool _useVisualDiff = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleDiffReload();
    });
  }

  @override
  void didUpdateWidget(GitDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleDiffReload();
    });
  }

  void _scheduleDiffReload({bool force = false}) {
    final change = widget.change;
    if (change == null) {
      if (_diffFuture != null || _cachedResult != null) {
        setState(() {
          _diffFuture = null;
          _cachedResult = null;
          _diffPath = null;
          _diffType = null;
        });
      }
      return;
    }
    final diskRevision = ref.read(gitDiskRevisionProvider);
    if (!force &&
        change.path == _diffPath &&
        change.type == _diffType &&
        widget.refreshToken == _refreshToken &&
        diskRevision == _diskRevision) {
      return;
    }

    setState(() {
      _diffPath = change.path;
      _diffType = change.type;
      _refreshToken = widget.refreshToken;
      _diskRevision = diskRevision;
      _useVisualDiff = gitDiffSupportsVisual(change.path);
      _diffFuture = _loadDiff(change).then((result) {
        if (mounted) {
          setState(() => _cachedResult = result);
        }
        return result;
      });
    });
  }

  Future<_DiffLoadResult> _loadDiff(GitChange change) async {
    final workspacePath = ref.read(settingsProvider).workspaceFolderPath;
    final fileKind = detectGitDiffFileKind(change.path);
    if (workspacePath == null || workspacePath.isEmpty) {
      return _DiffLoadResult(
        diff: '',
        title: '',
        fileKind: fileKind,
        snapshots: const GitDiffSnapshots(),
      );
    }

    final git = ref.read(gitServiceProvider);
    final diff = await git.diffPath(workspacePath, change);
    final title = await resolveGitDiffTitle(workspacePath, change);
    final snapshots = gitDiffSupportsVisual(change.path)
        ? await loadGitDiffSnapshots(
            git: git,
            workspacePath: workspacePath,
            change: change,
          )
        : const GitDiffSnapshots();
    return _DiffLoadResult(
      diff: diff,
      title: title,
      fileKind: fileKind,
      snapshots: snapshots,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(gitDiskRevisionProvider, (previous, next) {
      if (widget.change == null || previous == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleDiffReload(force: true);
      });
    });

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
                kLabelGitDiffPreview,
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

    final fileName = change.path.split('/').last;
    final supportsVisual = gitDiffSupportsVisual(change.path);
    final isResponseBodyFile = gitDiffIsResponseBodyFile(change.path);
    final canToggleRawDiff = supportsVisual && !isResponseBodyFile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: FutureBuilder<_DiffLoadResult>(
            future: _diffFuture,
            builder: (context, snapshot) {
              final title = snapshot.data?.title;
              final displayTitle = title != null && title.isNotEmpty
                  ? title
                  : fileName;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          change.path,
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      kHSpacer8,
                      _ChangeTypePill(type: change.type),
                    ],
                  ),
                  kVSpacer8,
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayTitle,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (canToggleRawDiff) ...[
                        kHSpacer8,
                        _DiffModeToggle(
                          useVisual: _useVisualDiff,
                          onChanged: (visual) {
                            setState(() => _useVisualDiff = visual);
                          },
                        ),
                      ],
                    ],
                  ),
                  if (displayTitle != fileName) ...[
                    kVSpacer5,
                    Text(
                      fileName,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FutureBuilder<_DiffLoadResult>(
              future: _diffFuture,
              builder: (context, snapshot) {
                final result = snapshot.data ?? _cachedResult;
                if (result == null &&
                    snapshot.connectionState != ConnectionState.done) {
                  return _GitDiffLoadingIndicator(scheme: scheme);
                }
                if (snapshot.hasError && result == null) {
                  return Center(
                    child: Text(
                      kLabelGitDiffEmpty,
                      style: textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  );
                }
                if (result == null) {
                  return _GitDiffLoadingIndicator(scheme: scheme);
                }

                final showVisual =
                    supportsVisual && (isResponseBodyFile || _useVisualDiff);
                if (showVisual) {
                  return GitVisualDiffView(
                    fileKind: result.fileKind,
                    snapshots: result.snapshots,
                  );
                }

                final diff = result.diff.trim();
                final rows = parseGitRawDiffRows(diff);
                if (diff.isEmpty || rows.isEmpty) {
                  return Center(
                    child: Text(
                      kLabelGitDiffEmpty,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return GitRawDiffView(
                  rows: rows,
                  leftColumnLabel: kLabelGitDiffOriginal,
                  rightColumnLabel: kLabelGitDiffCurrent,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _GitDiffLoadingIndicator extends StatelessWidget {
  const _GitDiffLoadingIndicator({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary.withValues(alpha: 0.7),
            ),
          ),
          kVSpacer10,
          Text(
            kLabelGitDiffLoading,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DiffModeToggle extends StatelessWidget {
  const _DiffModeToggle({required this.useVisual, required this.onChanged});

  final bool useVisual;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text(kLabelGitDiffVisual)),
        ButtonSegment(value: false, label: Text(kLabelGitDiffRaw)),
      ],
      selected: {useVisual},
      onSelectionChanged: (selection) {
        if (selection.isEmpty) return;
        onChanged(selection.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primaryContainer.withValues(alpha: 0.5);
          }
          return scheme.surfaceContainerHighest.withValues(alpha: 0.4);
        }),
      ),
    );
  }
}

class _ChangeTypePill extends StatelessWidget {
  const _ChangeTypePill({required this.type});

  final GitChangeType type;

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      GitChangeType.added => 'Added',
      GitChangeType.modified => 'Modified',
      GitChangeType.deleted => 'Removed',
      GitChangeType.untracked => 'New',
      GitChangeType.renamed => 'Renamed',
    };
    final highlight = getGitDiffHighlight(
      Theme.of(context).brightness,
      gitDiffChangeKind(type),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlight.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: highlight.foreground.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: highlight.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
