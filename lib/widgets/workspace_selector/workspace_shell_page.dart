import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/git/git_error.dart';
import 'package:apidash/git/services/git_service.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/widgets/workspace_selector/workspace_action_panel.dart';
import 'package:apidash/widgets/workspace_selector/workspace_recent_sidebar.dart';
import 'package:apidash/widgets/workspace_selector/workspace_right_panel.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

class WorkspaceShellPage extends HookConsumerWidget {
  const WorkspaceShellPage({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final busy = useState(false);
    final view = useState(WorkspaceRightView.welcome);
    final selectedRecentPath = useState<String?>(null);
    final savedWorkspaces =
        ref.watch(settingsProvider.select((s) => s.savedWorkspaces));

    Future<void> runBusy(Future<void> Function() action) async {
      busy.value = true;
      try {
        await action();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            getSnackBar(formatGitCollaborationError(e), color: kColorRed),
          );
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    Future<void> openRecent(SavedWorkspaceEntry entry) async {
      selectedRecentPath.value = entry.path;
      if (!await Directory(entry.path).exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            getSnackBar(kMsgWorkspaceRecentMissing, color: kColorRed),
          );
          final rest = savedWorkspaces
              .where((e) => p.normalize(e.path) != p.normalize(entry.path))
              .toList();
          await ref.read(settingsProvider.notifier).update(
                savedWorkspaces: rest,
              );
        }
        return;
      }
      await runBusy(() => onOpenWorkspace(entry.path));
    }

    void selectAction(WorkspaceSelectorAction action) {
      selectedRecentPath.value = null;
      view.value = viewForAction(action);
    }

    void goBack() {
      selectedRecentPath.value = null;
      view.value = WorkspaceRightView.welcome;
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: WorkspaceRecentSidebar(
                    workspaces: savedWorkspaces,
                    selectedPath: selectedRecentPath.value,
                    busy: busy.value,
                    onRecentSelected: openRecent,
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: WorkspaceRightPanel(
                    view: view.value,
                    busy: busy.value,
                    showCancel: showCancel,
                    onCancel: onCancel,
                    gitService: gitService,
                    onActionSelected: selectAction,
                    onBack: goBack,
                    onCreateSubmit: (path) =>
                        runBusy(() => onCreateWorkspace(path)),
                    onOpenSubmit: (path) =>
                        runBusy(() => onOpenWorkspace(path)),
                    onCloneSubmit: (url, parent, folderName) =>
                        runBusy(() async {
                      await onClone?.call(url, parent, folderName);
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
