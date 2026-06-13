import 'package:apidash/consts.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/widgets/expandable_section.dart';
import 'package:flutter/material.dart';

class GitRecentCommitsSection extends StatelessWidget {
  const GitRecentCommitsSection({
    super.key,
    required this.commits,
  });

  final List<GitLogEntry> commits;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = commits.isEmpty
        ? kLabelRecentCommits
        : '$kLabelRecentCommits (${commits.length})';

    return ExpandableSection(
      title: title,
      child: commits.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                kMsgGitNoCommits,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: commits.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.25),
                ),
                itemBuilder: (context, index) {
                  final entry = commits[index];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      '${entry.author} · ${entry.relativeTime}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
