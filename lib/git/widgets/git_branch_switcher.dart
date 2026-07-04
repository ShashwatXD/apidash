import 'package:apidash/git/consts.dart';
import 'package:apidash/git/widgets/git_sync_toolbar.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

const kGitCreateBranchMenuValue = '__git_create_branch__';

class GitBranchSwitcher extends StatelessWidget {
  const GitBranchSwitcher({
    super.key,
    required this.branches,
    required this.currentBranch,
    required this.busy,
    required this.onBranchSelected,
    required this.onCreateBranch,
  });

  final List<String> branches;
  final String? currentBranch;
  final bool busy;
  final ValueChanged<String> onBranchSelected;
  final VoidCallback onCreateBranch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = _displayBranch(currentBranch);

    return Material(
      color: scheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(20),
      child: PopupMenuButton<String>(
        enabled: !busy,
        tooltip: kLabelGitSwitchBranch,
        offset: const Offset(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (value) {
          if (value == kGitCreateBranchMenuValue) {
            onCreateBranch();
            return;
          }
          if (value == currentBranch) return;
          onBranchSelected(value);
        },
        itemBuilder: (context) {
          final items = <PopupMenuEntry<String>>[];
          final sorted = [...branches]..sort();
          if (currentBranch != null &&
              currentBranch!.isNotEmpty &&
              !sorted.contains(currentBranch)) {
            sorted.insert(0, currentBranch!);
          }

          for (final branch in sorted) {
            final isCurrent = branch == currentBranch;
            items.add(
              PopupMenuItem<String>(
                value: branch,
                height: 40,
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: isCurrent
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: scheme.primary,
                            )
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        branch,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (items.isNotEmpty) {
            items.add(const PopupMenuDivider(height: 8));
          }
          items.add(
            PopupMenuItem<String>(
              value: kGitCreateBranchMenuValue,
              height: 40,
              child: Row(
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  kHSpacer10,
                  Text(
                    kLabelGitNewBranch,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
          return items;
        },
        child: SizedBox(
          height: kGitPanelHeaderBranchRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  Icons.call_split_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                kHSpacer8,
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _displayBranch(String? branch) {
    final trimmed = branch?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return kLabelGitNoBranch;
  }
}
