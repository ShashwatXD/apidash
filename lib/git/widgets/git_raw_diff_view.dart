import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

class GitRawDiffRow {
  const GitRawDiffRow({
    this.oldLine,
    this.newLine,
    this.isDeletion = false,
    this.isAddition = false,
  });

  final String? oldLine;
  final String? newLine;
  final bool isDeletion;
  final bool isAddition;
}

List<String> visibleGitRawDiffLines(String diff) {
  return diff
      .split('\n')
      .where((line) => !_isGitRawDiffMetadataLine(line))
      .toList();
}

List<GitRawDiffRow> parseGitRawDiffRows(String diff) {
  final rows = <GitRawDiffRow>[];
  for (final line in visibleGitRawDiffLines(diff)) {
    if (line.startsWith('-')) {
      rows.add(GitRawDiffRow(oldLine: line.substring(1), isDeletion: true));
    } else if (line.startsWith('+')) {
      rows.add(GitRawDiffRow(newLine: line.substring(1), isAddition: true));
    } else {
      final content = line.startsWith(' ') ? line.substring(1) : line;
      rows.add(GitRawDiffRow(oldLine: content, newLine: content));
    }
  }
  return rows;
}

bool _isGitRawDiffMetadataLine(String line) {
  if (line.isEmpty) return false;
  return line.startsWith('diff --git ') ||
      line.startsWith('index ') ||
      line.startsWith('--- ') ||
      line.startsWith('+++ ') ||
      line.startsWith('new file mode ') ||
      line.startsWith('deleted file mode ') ||
      line.startsWith('similarity index ') ||
      line.startsWith('rename from ') ||
      line.startsWith('rename to ') ||
      line.startsWith('Binary files ') ||
      line.startsWith('@@') ||
      line.startsWith(r'\ No newline at end of file');
}

class GitRawDiffView extends StatelessWidget {
  const GitRawDiffView({
    super.key,
    required this.rows,
    required this.leftColumnLabel,
    required this.rightColumnLabel,
  });

  final List<GitRawDiffRow> rows;
  final String leftColumnLabel;
  final String rightColumnLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var oldLineNum = 0;
    var newLineNum = 0;
    final numbered = <({GitRawDiffRow row, int? oldNum, int? newNum})>[];

    for (final row in rows) {
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
      numbered.add((row: row, oldNum: oldNum, newNum: newNum));
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
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
                      leftColumnLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rightColumnLabel,
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
                itemCount: numbered.length,
                itemBuilder: (context, index) {
                  final item = numbered[index];
                  return _GitRawDiffRowView(
                    row: item.row,
                    oldLineNum: item.oldNum,
                    newLineNum: item.newNum,
                    scheme: Theme.of(context).colorScheme,
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

class _GitRawDiffRowView extends StatelessWidget {
  const _GitRawDiffRowView({
    required this.row,
    required this.oldLineNum,
    required this.newLineNum,
    required this.scheme,
  });

  final GitRawDiffRow row;
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
            child: _GitRawDiffCell(
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
            child: _GitRawDiffCell(
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

class _GitRawDiffCell extends StatelessWidget {
  const _GitRawDiffCell({
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
    final brightness = Theme.of(context).brightness;
    final highlight = isAdded
        ? getGitDiffHighlight(brightness, GitDiffChangeKind.added)
        : isRemoved
        ? getGitDiffHighlight(brightness, GitDiffChangeKind.removed)
        : null;

    final displayText = text ?? '';
    final lineColor =
        highlight?.foreground ??
        getGitDiffHighlight(brightness, GitDiffChangeKind.neutral).foreground;

    return Container(
      color: highlight?.background,
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
                        color: lineColor,
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: SelectableText(
              displayText,
              style: kCodeStyle.copyWith(
                fontSize: 12,
                height: 1.5,
                color:
                    highlight?.foreground ??
                    scheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
