import 'package:apidash/git/services/git_service.dart';
import 'package:apidash/widgets/workspace_selector/workspace_action_panel.dart';
import 'package:apidash/widgets/workspace_selector/workspace_decor.dart';
import 'package:apidash/widgets/workspace_selector/workspace_flows.dart';
import 'package:flutter/material.dart';

enum WorkspaceRightView { welcome, newLocal, clone, open }

class WorkspaceRightPanel extends StatelessWidget {
  const WorkspaceRightPanel({
    super.key,
    required this.view,
    required this.busy,
    required this.onActionSelected,
    required this.onBack,
    required this.onCreateSubmit,
    required this.onOpenSubmit,
    required this.onCloneSubmit,
    this.gitService,
    this.onCancel,
    this.showCancel = false,
  });

  final WorkspaceRightView view;
  final bool busy;
  final void Function(WorkspaceSelectorAction action) onActionSelected;
  final VoidCallback onBack;
  final Future<void> Function(String path) onCreateSubmit;
  final Future<void> Function(String path) onOpenSubmit;
  final Future<void> Function(
    String remoteUrl,
    String parentDirectory,
    String folderName,
  ) onCloneSubmit;
  final GitService? gitService;
  final VoidCallback? onCancel;
  final bool showCancel;

  @override
  Widget build(BuildContext context) {
    return WorkspaceMorphTransition(
      transitionKey: view,
      child: switch (view) {
            WorkspaceRightView.welcome => WorkspaceActionPanel(
                busy: busy,
                showCancel: showCancel,
                onCancel: onCancel,
                onActionSelected: onActionSelected,
              ),
            WorkspaceRightView.newLocal => WorkspaceNewFlow(
                busy: busy,
                onBack: onBack,
                onSubmit: onCreateSubmit,
              ),
            WorkspaceRightView.clone => WorkspaceCloneFlow(
                busy: busy,
                onBack: onBack,
                gitService: gitService,
                onSubmit: onCloneSubmit,
              ),
            WorkspaceRightView.open => WorkspaceOpenFlow(
                busy: busy,
                onBack: onBack,
                onSubmit: onOpenSubmit,
              ),
          },
    );
  }
}

WorkspaceRightView viewForAction(WorkspaceSelectorAction action) {
  return switch (action) {
    WorkspaceSelectorAction.newLocal => WorkspaceRightView.newLocal,
    WorkspaceSelectorAction.clone => WorkspaceRightView.clone,
    WorkspaceSelectorAction.open => WorkspaceRightView.open,
  };
}

WorkspaceSelectorAction? actionForView(WorkspaceRightView view) {
  return switch (view) {
    WorkspaceRightView.welcome => null,
    WorkspaceRightView.newLocal => WorkspaceSelectorAction.newLocal,
    WorkspaceRightView.clone => WorkspaceSelectorAction.clone,
    WorkspaceRightView.open => WorkspaceSelectorAction.open,
  };
}
