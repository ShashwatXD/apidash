import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

class GitDiffChangedField {
  const GitDiffChangedField({
    required this.label,
    required this.kind,
    this.detail,
  });

  final String label;
  final GitDiffChangeKind kind;
  final String? detail;
}

String gitDiffChangeKindLabel(GitDiffChangeKind kind) {
  return switch (kind) {
    GitDiffChangeKind.added => 'Added',
    GitDiffChangeKind.removed => 'Removed',
    GitDiffChangeKind.modified => 'Modified',
    GitDiffChangeKind.renamed => 'Renamed',
    GitDiffChangeKind.neutral => 'Unchanged',
  };
}

class GitDiffChangeBadge extends StatelessWidget {
  const GitDiffChangeBadge({super.key, required this.kind});

  final GitDiffChangeKind kind;

  @override
  Widget build(BuildContext context) {
    final highlight = getGitDiffHighlight(Theme.of(context).brightness, kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: highlight.foreground.withValues(alpha: 0.28)),
      ),
      child: Text(
        gitDiffChangeKindLabel(kind),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: highlight.foreground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Compact summary of what changed, shown above the side-by-side panels.
class GitDiffChangeSummaryBar extends StatelessWidget {
  const GitDiffChangeSummaryBar({super.key, required this.changes});

  final List<GitDiffChangedField> changes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (changes.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          'No field-level differences detected',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final added = changes.where((c) => c.kind == GitDiffChangeKind.added).length;
    final removed =
        changes.where((c) => c.kind == GitDiffChangeKind.removed).length;
    final modified =
        changes.where((c) => c.kind == GitDiffChangeKind.modified).length;

    final counts = <String>[
      if (added > 0) '$added added',
      if (removed > 0) '$removed removed',
      if (modified > 0) '$modified modified',
    ].join(' · ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Changes · $counts',
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          kVSpacer8,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final change in changes)
                _ChangeChip(change: change),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.change});

  final GitDiffChangedField change;

  @override
  Widget build(BuildContext context) {
    final highlight =
        getGitDiffHighlight(Theme.of(context).brightness, change.kind);
    final detail = change.detail?.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: highlight.foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            change.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: highlight.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          kHSpacer8,
          Text(
            gitDiffChangeKindLabel(change.kind),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlight.foreground.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            kHSpacer8,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                detail,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class GitDiffSectionHeader extends StatelessWidget {
  const GitDiffSectionHeader({
    super.key,
    required this.label,
    this.change,
    this.subtitle,
    this.trailing,
  });

  final String label;
  final GitDiffChangeKind? change;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (change != null) ...[
                      const SizedBox(width: 8),
                      GitDiffChangeBadge(kind: change!),
                    ],
                  ],
                ),
                if (subtitle case final text? when text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      text,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class GitDiffKvTableHeader extends StatelessWidget {
  const GitDiffKvTableHeader({
    super.key,
    this.keyLabel = 'Key',
    this.valueLabel = 'Value',
  });

  final String keyLabel;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(keyLabel, style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: Text(valueLabel, style: style)),
        ],
      ),
    );
  }
}

class GitDiffBoxedContent extends StatelessWidget {
  const GitDiffBoxedContent({
    super.key,
    required this.child,
    this.change,
    this.margin = EdgeInsets.zero,
    this.minHeight,
  });

  final Widget child;
  final GitDiffChangeKind? change;
  final EdgeInsetsGeometry margin;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    final Color border;

    if (change != null) {
      final highlight =
          getGitDiffHighlight(Theme.of(context).brightness, change!);
      background = highlight.background;
      border = highlight.foreground.withValues(alpha: 0.22);
    } else {
      background = scheme.surfaceContainerHighest.withValues(alpha: 0.45);
      border = scheme.outlineVariant.withValues(alpha: 0.4);
    }

    return Container(
      margin: margin,
      constraints:
          minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}
