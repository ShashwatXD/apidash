import 'package:apidash/git/services/git_service.dart';
import 'package:apidash/widgets/workspace_selector/workspace_shell_page.dart';
import 'package:flutter/material.dart';

/// Desktop workspace picker shown on first launch and from the workspace menu.
class WorkspaceSelector extends StatelessWidget {
  const WorkspaceSelector({
    super.key,
    required this.onCreateWorkspace,
    required this.onOpenWorkspace,
    this.onClone,
    this.onCancel,
    this.showCancel = true,
    this.gitService,
  });

  final Future<void> Function(String path) onCreateWorkspace;
  final Future<void> Function(String path) onOpenWorkspace;
  final Future<void> Function(
    String remoteUrl,
    String parentDirectory,
    String folderName,
  )? onClone;
  final Future<void> Function()? onCancel;
  final bool showCancel;
  final GitService? gitService;

  @override
  Widget build(BuildContext context) {
    return WorkspaceShellPage(
      onCreateWorkspace: onCreateWorkspace,
      onOpenWorkspace: onOpenWorkspace,
      onClone: onClone,
      onCancel: onCancel,
      showCancel: showCancel,
      gitService: gitService,
    );
  }
}
