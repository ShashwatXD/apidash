import 'package:flutter/material.dart';

import '../../consts.dart';

class GitDiffSideBySideShell extends StatelessWidget {
  const GitDiffSideBySideShell({
    super.key,
    required this.original,
    required this.current,
  });

  final Widget original;
  final Widget current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
                      kLabelGitDiffOriginal,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      kLabelGitDiffCurrent,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: original),
                  Container(
                    width: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                  Expanded(child: current),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
