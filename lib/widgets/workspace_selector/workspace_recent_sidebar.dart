import 'package:apidash/consts.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class WorkspaceRecentSidebar extends StatelessWidget {
  const WorkspaceRecentSidebar({
    super.key,
    required this.workspaces,
    required this.selectedPath,
    required this.busy,
    required this.onRecentSelected,
  });

  final List<SavedWorkspaceEntry> workspaces;
  final String? selectedPath;
  final bool busy;
  final void Function(SavedWorkspaceEntry entry) onRecentSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          kMsgWorkspaceGetStarted,
          style: textTheme.headlineLarge,
        ),
        kVSpacer40,
        Text(
          'RECENT WORKSPACES',
          style: textTheme.labelSmall,
        ),
        kVSpacer20,
        if (workspaces.isEmpty)
          Text(
            kMsgWorkspaceRecentsEmpty,
            style: textTheme.bodySmall,
          )
        else
          ...workspaces.map((entry) {
            final isSelected = selectedPath != null &&
                p.normalize(selectedPath!) == p.normalize(entry.path);
            return _RecentTile(
              entry: entry,
              isSelected: isSelected,
              enabled: !busy,
              onTap: () => onRecentSelected(entry),
            );
          }),
      ],
    );
  }
}

class _RecentTile extends StatefulWidget {
  const _RecentTile({
    required this.entry,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final SavedWorkspaceEntry entry;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_RecentTile> createState() => _RecentTileState();
}

class _RecentTileState extends State<_RecentTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = widget.isSelected || _hovered;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: highlighted
              ? scheme.surfaceContainerHigh
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: highlighted
                  ? scheme.outlineVariant
                  : Colors.transparent,
            ),
          ),
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: highlighted ? scheme.primary : scheme.outline,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kTextStyleLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: highlighted
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.entry.path,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: kCodeStyle.copyWith(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
