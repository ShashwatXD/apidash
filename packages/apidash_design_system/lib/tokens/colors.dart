import 'package:flutter/material.dart';

final kColorTransparentState =
    WidgetStateProperty.all<Color>(Colors.transparent);
const kColorTransparent = Colors.transparent;
const kColorWhite = Colors.white;
const kColorBlack = Colors.black;
const kColorRed = Colors.red;
final kColorLightDanger = Colors.red.withValues(alpha: 0.9);
const kColorDarkDanger = Color(0xffcf6679);

const kColorSchemeSeed = Colors.blue;

final kColorStatusCodeDefault = Colors.grey.shade700;
final kColorStatusCode200 = Colors.green.shade800;
final kColorStatusCode300 = Colors.blue.shade800;
final kColorStatusCode400 = Colors.red.shade800;
final kColorStatusCode500 = Colors.amber.shade900;

final kColorHttpMethodGet = Colors.green.shade800;
final kColorHttpMethodHead = kColorHttpMethodGet;
final kColorHttpMethodPost = Colors.blue.shade800;
final kColorHttpMethodPut = Colors.amber.shade900;
final kColorHttpMethodPatch = kColorHttpMethodPut;
final kColorHttpMethodDelete = Colors.red.shade800;
final kColorHttpMethodOptions = Colors.deepPurple.shade800;

final kColorGQL = Colors.pink.shade600;

// Git diff — medium tints in light mode, GitHub dark palette in dark mode.
const kColorGitDiffAddedBgLight = Color(0xFFBBF0C8);
const kColorGitDiffAddedFgLight = Color(0xFF0B5323);
const kColorGitDiffAddedBgDark = Color(0xFF033A16);
const kColorGitDiffAddedFgDark = Color(0xFF7EE787);

const kColorGitDiffRemovedBgLight = Color(0xFFFFD1CD);
const kColorGitDiffRemovedFgLight = Color(0xFF8B1820);
const kColorGitDiffRemovedBgDark = Color(0xFF67060C);
const kColorGitDiffRemovedFgDark = Color(0xFFFFA198);

const kColorGitDiffModifiedBgLight = Color(0xFFFFE08A);
const kColorGitDiffModifiedFgLight = Color(0xFF7B4E00);
const kColorGitDiffModifiedBgDark = Color(0xFF341A00);
const kColorGitDiffModifiedFgDark = Color(0xFFE3B341);

const kColorGitDiffRenamedBgLight = Color(0xFF99D1FF);
const kColorGitDiffRenamedFgLight = Color(0xFF0349B4);
const kColorGitDiffRenamedBgDark = Color(0xFF051D4D);
const kColorGitDiffRenamedFgDark = Color(0xFF79C0FF);

const kColorGitDiffNeutralFgLight = Color(0xFF454F59);
const kColorGitDiffNeutralFgDark = Color(0xFF8B949E);

enum GitDiffChangeKind { added, removed, modified, renamed, neutral }

class GitDiffHighlight {
  const GitDiffHighlight({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}

GitDiffHighlight getGitDiffHighlight(
  Brightness brightness,
  GitDiffChangeKind kind,
) {
  final isDark = brightness == Brightness.dark;
  return switch (kind) {
    GitDiffChangeKind.added => GitDiffHighlight(
        background:
            isDark ? kColorGitDiffAddedBgDark : kColorGitDiffAddedBgLight,
        foreground:
            isDark ? kColorGitDiffAddedFgDark : kColorGitDiffAddedFgLight,
      ),
    GitDiffChangeKind.removed => GitDiffHighlight(
        background:
            isDark ? kColorGitDiffRemovedBgDark : kColorGitDiffRemovedBgLight,
        foreground:
            isDark ? kColorGitDiffRemovedFgDark : kColorGitDiffRemovedFgLight,
      ),
    GitDiffChangeKind.modified => GitDiffHighlight(
        background: isDark
            ? kColorGitDiffModifiedBgDark
            : kColorGitDiffModifiedBgLight,
        foreground: isDark
            ? kColorGitDiffModifiedFgDark
            : kColorGitDiffModifiedFgLight,
      ),
    GitDiffChangeKind.renamed => GitDiffHighlight(
        background:
            isDark ? kColorGitDiffRenamedBgDark : kColorGitDiffRenamedBgLight,
        foreground:
            isDark ? kColorGitDiffRenamedFgDark : kColorGitDiffRenamedFgLight,
      ),
    GitDiffChangeKind.neutral => GitDiffHighlight(
        background: kColorTransparent,
        foreground:
            isDark ? kColorGitDiffNeutralFgDark : kColorGitDiffNeutralFgLight,
      ),
  };
}

const kHintOpacity = 0.6;
const kForegroundOpacity = 0.05;
const kOverlayBackgroundOpacity = 0.5;
const kOpacityDarkModeBlend = 0.4;
