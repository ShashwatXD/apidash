import 'package:apidash/consts.dart';
import 'package:apidash/git/models/git_change_tree.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

const _guideWidth = 9.0;
const _maxGuideWidth = 28.0;

class GitChangesTree extends StatefulWidget {
  const GitChangesTree({
    super.key,
    required this.roots,
    required this.selectedPaths,
    required this.previewPath,
    required this.busy,
    required this.onSelectionChanged,
    required this.onFilePreview,
    this.enableSelection = true,
  });

  final List<GitTreeNode> roots;
  final Set<String> selectedPaths;
  final String? previewPath;
  final bool busy;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<GitChange> onFilePreview;
  final bool enableSelection;

  @override
  State<GitChangesTree> createState() => _GitChangesTreeState();
}

class _GitChangesTreeState extends State<GitChangesTree> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    for (final root in widget.roots) {
      _expanded.add(root.path);
    }
  }

  @override
  void didUpdateWidget(GitChangesTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final root in widget.roots) {
      _expanded.add(root.path);
    }
  }

  void _togglePath(String path, bool selected) {
    final next = Set<String>.from(widget.selectedPaths);
    if (selected) {
      next.add(path);
    } else {
      next.remove(path);
    }
    widget.onSelectionChanged(next);
  }

  void _toggleFolder(GitTreeNode folder, bool? value) {
    final paths = folder.filePaths.toList();
    final next = Set<String>.from(widget.selectedPaths);
    if (value == true) {
      next.addAll(paths);
    } else {
      next.removeAll(paths);
    }
    widget.onSelectionChanged(next);
  }

  void _toggleSelectAll(bool? value) {
    final allPaths = widget.roots.expand((node) => node.filePaths).toSet();
    widget.onSelectionChanged(value == true ? allPaths : {});
  }

  bool? get _selectAllState {
    final allPaths = widget.roots.expand((n) => n.filePaths).toList();
    if (allPaths.isEmpty) return false;
    final count = allPaths.where(widget.selectedPaths.contains).length;
    if (count == 0) return false;
    if (count == allPaths.length) return true;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  kLabelChanges,
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${widget.selectedPaths.length}',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: widget.enableSelection
              ? InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: widget.busy
                      ? null
                      : () => _toggleSelectAll(!(_selectAllState ?? false)),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        _SelectionRing(
                          selected: _selectAllState == true,
                          partial: _selectAllState == null,
                          onTap: widget.busy
                              ? null
                              : () =>
                                  _toggleSelectAll(!(_selectAllState ?? false)),
                        ),
                        kHSpacer6,
                        Text(
                          kLabelSelectAll,
                          style: textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (widget.enableSelection) const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
            children: [
              for (var i = 0; i < widget.roots.length; i++)
                _TreeNodeTile(
                  node: widget.roots[i],
                  depth: 0,
                  guidePrefix: const [],
                  isLast: i == widget.roots.length - 1,
                  expanded: _expanded,
                  selectedPaths: widget.selectedPaths,
                  previewPath: widget.previewPath,
                  busy: widget.busy,
                  enableSelection: widget.enableSelection,
                  onToggleExpand: (path) {
                    setState(() {
                      if (_expanded.contains(path)) {
                        _expanded.remove(path);
                      } else {
                        _expanded.add(path);
                      }
                    });
                  },
                  onToggleFolder: _toggleFolder,
                  onToggleFile: _togglePath,
                  onFilePreview: widget.onFilePreview,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TreeNodeTile extends StatelessWidget {
  const _TreeNodeTile({
    required this.node,
    required this.depth,
    required this.guidePrefix,
    required this.isLast,
    required this.expanded,
    required this.selectedPaths,
    required this.previewPath,
    required this.busy,
    required this.enableSelection,
    required this.onToggleExpand,
    required this.onToggleFolder,
    required this.onToggleFile,
    required this.onFilePreview,
  });

  final GitTreeNode node;
  final int depth;
  final List<bool> guidePrefix;
  final bool isLast;
  final Set<String> expanded;
  final Set<String> selectedPaths;
  final String? previewPath;
  final bool busy;
  final bool enableSelection;
  final ValueChanged<String> onToggleExpand;
  final void Function(GitTreeNode folder, bool? value) onToggleFolder;
  final void Function(String path, bool selected) onToggleFile;
  final ValueChanged<GitChange> onFilePreview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final guideColor = scheme.primary.withValues(alpha: 0.38);

    if (!node.isFile) {
      final isOpen = expanded.contains(node.path);
      final checkState = folderSelectionState(node, selectedPaths);
      final summary = node.summary;
      final representative = node.representativeChange;
      final isPreview = representative != null &&
          previewPath == representative.path;
      final folderFg = _folderForeground(
        scheme: scheme,
        summary: summary,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: isPreview
                ? scheme.primaryContainer.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: busy
                  ? null
                  : () {
                      onToggleExpand(node.path);
                      if (representative != null) {
                        onFilePreview(representative);
                      }
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    if (depth > 0)
                      _TreeGuide(
                        prefix: guidePrefix,
                        isLast: isLast,
                        color: guideColor,
                      ),
                    if (enableSelection)
                      _SelectionRing(
                        selected: checkState == true,
                        partial: checkState == null,
                        onTap: busy
                            ? null
                            : () => onToggleFolder(
                                  node,
                                  checkState == true ? false : true,
                                ),
                      ),
                    if (enableSelection) kHSpacer4,
                    Icon(
                      summary != null && summary.isUniformDeleted
                          ? Icons.folder_off_outlined
                          : isOpen
                              ? Icons.folder_open_rounded
                              : Icons.folder_outlined,
                      size: 14,
                      color: folderFg ?? guideColor,
                    ),
                    kHSpacer4,
                    Expanded(
                      child: Tooltip(
                        message: node.path,
                        child: Text(
                          node.displayLabel,
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: folderFg,
                            decoration: summary != null &&
                                    summary.isUniformDeleted
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: folderFg,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (node.showsChangeBadges &&
                        summary != null &&
                        !summary.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, right: 2),
                        child: _FolderChangeBadges(summary: summary),
                      ),
                    Icon(
                      isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: scheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isOpen)
            for (var i = 0; i < node.children.length; i++)
              _TreeNodeTile(
                node: node.children[i],
                depth: depth + 1,
                guidePrefix: [...guidePrefix, !isLast],
                isLast: i == node.children.length - 1,
                expanded: expanded,
                selectedPaths: selectedPaths,
                previewPath: previewPath,
                busy: busy,
                enableSelection: enableSelection,
                onToggleExpand: onToggleExpand,
                onToggleFolder: onToggleFolder,
                onToggleFile: onToggleFile,
                onFilePreview: onFilePreview,
              ),
        ],
      );
    }

    final change = node.change!;
    final isPreview = previewPath == node.path;
    final isSelected = selectedPaths.contains(node.path);
    final label = node.displayLabel.isNotEmpty
        ? node.displayLabel
        : change.path.split('/').last;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: isPreview
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: busy ? null : () => onFilePreview(change),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
            child: Row(
              children: [
                if (depth > 0)
                  _TreeGuide(
                    prefix: guidePrefix,
                    isLast: isLast,
                    color: guideColor,
                  ),
                if (enableSelection)
                  _SelectionRing(
                    selected: isSelected,
                    onTap: busy
                        ? null
                        : () => onToggleFile(node.path, !isSelected),
                  ),
                if (enableSelection) kHSpacer4,
                Expanded(
                  child: Tooltip(
                    message: change.path,
                    child: Text(
                      label,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight:
                            isPreview ? FontWeight.w600 : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 10),
                  child: _ChangeTypeBadge(type: change.type),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeGuide extends StatelessWidget {
  const _TreeGuide({
    required this.prefix,
    required this.isLast,
    required this.color,
  });

  final List<bool> prefix;
  final bool isLast;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final full = prefix.length * _guideWidth + _guideWidth;
    final width = full.clamp(0, _maxGuideWidth).toDouble();
    return SizedBox(
      width: width,
      height: 22,
      child: CustomPaint(
        painter: _TreeGuidePainter(
          prefix: prefix,
          isLast: isLast,
          color: color,
        ),
      ),
    );
  }
}

class _TreeGuidePainter extends CustomPainter {
  _TreeGuidePainter({
    required this.prefix,
    required this.isLast,
    required this.color,
  });

  final List<bool> prefix;
  final bool isLast;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (var i = 0; i < prefix.length; i++) {
      if (!prefix[i]) continue;
      final x = i * _guideWidth + _guideWidth / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    final branchX = prefix.length * _guideWidth + _guideWidth / 2;
    final midY = size.height / 2;

    if (isLast) {
      canvas.drawLine(
        Offset(branchX, 0),
        Offset(branchX, midY),
        paint,
      );
      canvas.drawLine(
        Offset(branchX, midY),
        Offset(size.width, midY),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(branchX, 0),
        Offset(branchX, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(branchX, midY),
        Offset(size.width, midY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TreeGuidePainter oldDelegate) {
    return oldDelegate.prefix != prefix ||
        oldDelegate.isLast != isLast ||
        oldDelegate.color != color;
  }
}

class _SelectionRing extends StatelessWidget {
  const _SelectionRing({
    required this.selected,
    this.partial = false,
    this.onTap,
  });

  final bool selected;
  final bool partial;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 16,
        height: 16,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected || partial ? scheme.primary : Colors.transparent,
            border: Border.all(
              color: selected || partial ? scheme.primary : scheme.outline,
              width: 1.2,
            ),
          ),
          child: partial
              ? Icon(Icons.remove, size: 10, color: scheme.onPrimary)
              : selected
                  ? Icon(Icons.check, size: 10, color: scheme.onPrimary)
                  : null,
        ),
      ),
    );
  }
}

class _FolderChangeBadges extends StatelessWidget {
  const _FolderChangeBadges({required this.summary});

  final GitFolderSummary summary;

  @override
  Widget build(BuildContext context) {
    final types = summary.badgeTypes;
    if (types.isEmpty) return const SizedBox.shrink();

    // Uniform folders: one clear letter. Mixed: compact counts (2D 1M).
    if (summary.isUniform) {
      return _ChangeTypeBadge(type: types.first);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < types.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _ChangeTypeBadge(
            type: types[i],
            count: summary.counts[types[i]],
          ),
        ],
      ],
    );
  }
}

class _ChangeTypeBadge extends StatelessWidget {
  const _ChangeTypeBadge({
    required this.type,
    this.count,
  });

  final GitChangeType type;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final (letter, kind) = switch (type) {
      GitChangeType.added || GitChangeType.untracked => (
          'A',
          GitDiffChangeKind.added,
        ),
      GitChangeType.modified => ('M', GitDiffChangeKind.modified),
      GitChangeType.deleted => ('D', GitDiffChangeKind.removed),
      GitChangeType.renamed => ('R', GitDiffChangeKind.renamed),
    };
    final fg =
        getGitDiffHighlight(Theme.of(context).brightness, kind).foreground;
    final label = count != null && count! > 1 ? '$count$letter' : letter;

    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: fg,
      ),
    );
  }
}

Color? _folderForeground({
  required ColorScheme scheme,
  required GitFolderSummary? summary,
}) {
  if (summary == null || summary.isEmpty) return null;
  if (summary.isUniformDeleted) {
    return getGitDiffHighlight(
      scheme.brightness,
      GitDiffChangeKind.removed,
    ).foreground;
  }
  if (summary.isUniformAdded) {
    return getGitDiffHighlight(
      scheme.brightness,
      GitDiffChangeKind.added,
    ).foreground;
  }
  return null;
}
