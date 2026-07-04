import 'package:apidash/consts.dart';
import 'package:apidash/widgets/workspace_selector/workspace_decor.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

enum WorkspaceSelectorAction { newLocal, clone, open }

class WorkspaceActionPanel extends StatelessWidget {
  const WorkspaceActionPanel({
    super.key,
    required this.onActionSelected,
    this.onCancel,
    this.showCancel = false,
    this.busy = false,
  });

  final void Function(WorkspaceSelectorAction action) onActionSelected;
  final VoidCallback? onCancel;
  final bool showCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkspaceActionCard(
          icon: Icons.create_new_folder_rounded,
          title: kLabelWorkspaceNew,
          isPrimary: true,
          filledIcon: true,
          enabled: !busy,
          onTap: () => onActionSelected(WorkspaceSelectorAction.newLocal),
        ),
        kVSpacer20,
        WorkspaceActionCard(
          icon: Icons.account_tree_outlined,
          title: kLabelWorkspaceClone,
          enabled: !busy,
          onTap: () => onActionSelected(WorkspaceSelectorAction.clone),
        ),
        kVSpacer20,
        WorkspaceActionCard(
          icon: Icons.folder_open_outlined,
          title: kLabelWorkspaceOpen,
          enabled: !busy,
          onTap: () => onActionSelected(WorkspaceSelectorAction.open),
        ),
        if (showCancel && onCancel != null) ...[
          kVSpacer40,
          Center(
            child: TextButton(
              onPressed: busy ? null : onCancel,
              style: TextButton.styleFrom(
                foregroundColor: scheme.outline,
              ),
              child: Text(
                kLabelCancel,
                style: kTextStyleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.outline,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String workspaceActionSubtitle(WorkspaceSelectorAction action) {
  return switch (action) {
    WorkspaceSelectorAction.newLocal =>
      'Choose where to store requests and environments.',
    WorkspaceSelectorAction.clone =>
      'Clone a remote repository into a local folder.',
    WorkspaceSelectorAction.open =>
      'Open a folder that already contains API Dash files.',
  };
}

String workspaceActionTitle(WorkspaceSelectorAction action) {
  return switch (action) {
    WorkspaceSelectorAction.newLocal => kLabelWorkspaceNew,
    WorkspaceSelectorAction.clone => kLabelWorkspaceClone,
    WorkspaceSelectorAction.open => kLabelWorkspaceOpen,
  };
}
