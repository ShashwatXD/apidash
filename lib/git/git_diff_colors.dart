import 'package:apidash/git/models/git_models.dart';
import 'package:flutter/material.dart';

enum GitDiffChangeKind { added, removed, modified, renamed, neutral }

class GitDiffHighlight {
  const GitDiffHighlight({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

abstract final class GitDiffColors {
  static GitDiffHighlight highlight(
    Brightness brightness,
    GitDiffChangeKind kind,
  ) {
    final isDark = brightness == Brightness.dark;
    return switch (kind) {
      GitDiffChangeKind.added => GitDiffHighlight(
          background: isDark ? const Color(0xFF033A16) : const Color(0xFFE6FFEC),
          foreground: isDark ? const Color(0xFF7EE787) : const Color(0xFF116329),
        ),
      GitDiffChangeKind.removed => GitDiffHighlight(
          background: isDark ? const Color(0xFF67060C) : const Color(0xFFFFEBE9),
          foreground: isDark ? const Color(0xFFFFA198) : const Color(0xFF82071E),
        ),
      GitDiffChangeKind.modified => GitDiffHighlight(
          background: isDark ? const Color(0xFF341A00) : const Color(0xFFFFF8C5),
          foreground: isDark ? const Color(0xFFE3B341) : const Color(0xFF9A6700),
        ),
      GitDiffChangeKind.renamed => GitDiffHighlight(
          background: isDark ? const Color(0xFF051D4D) : const Color(0xFFDDF4FF),
          foreground: isDark ? const Color(0xFF79C0FF) : const Color(0xFF0969DA),
        ),
      GitDiffChangeKind.neutral => GitDiffHighlight(
          background: Colors.transparent,
          foreground: isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
        ),
    };
  }

  static GitDiffChangeKind forGitChangeType(GitChangeType type) {
    return switch (type) {
      GitChangeType.added || GitChangeType.untracked => GitDiffChangeKind.added,
      GitChangeType.deleted => GitDiffChangeKind.removed,
      GitChangeType.modified => GitDiffChangeKind.modified,
      GitChangeType.renamed => GitDiffChangeKind.renamed,
    };
  }
}
