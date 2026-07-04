import 'dart:async';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/git/services/git_service.dart';
import 'package:apidash/services/services.dart';
import 'package:apidash/widgets/workspace_selector/workspace_path_preview.dart';
import 'package:apidash/widgets/workspace_selector/workspace_action_panel.dart';
import 'package:apidash/widgets/workspace_selector/workspace_decor.dart';
import 'package:apidash/widgets/workspace_selector/workspace_shared.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:path/path.dart' as p;

class WorkspaceNewFlow extends HookWidget {
  const WorkspaceNewFlow({
    super.key,
    required this.busy,
    required this.onBack,
    required this.onSubmit,
  });

  final bool busy;
  final VoidCallback onBack;
  final Future<void> Function(String path) onSubmit;

  @override
  Widget build(BuildContext context) {
    final parentPath = useState<String?>(null);
    final parentController = useTextEditingController();
    final nameController = useTextEditingController();
    useListenable(nameController);

    final workspaceName = nameController.text.trim();
    final finalPath = parentPath.value == null
        ? null
        : workspaceName.isEmpty
            ? parentPath.value!
            : p.join(parentPath.value!, workspaceName);

    final pathExists = useState<bool?>(null);
    useEffect(() {
      if (finalPath == null || workspaceName.isEmpty) {
        pathExists.value = null;
        return null;
      }
      var cancelled = false;
      Future<void>(() async {
        final exists = await Directory(finalPath).exists();
        if (!cancelled) pathExists.value = exists;
      });
      return () {
        cancelled = true;
      };
    }, [finalPath, workspaceName]);

    final canSubmit = !busy &&
        parentPath.value != null &&
        (workspaceName.isEmpty || isValidWorkspaceFolderName(workspaceName)) &&
        pathExists.value != true;

    return _FlowScaffold(
      action: WorkspaceSelectorAction.newLocal,
      children: [
        const WorkspaceFieldLabel(label: kLabelWorkspaceLocation),
        kVSpacer5,
        WorkspaceFolderPickerRow(
          controller: parentController,
          enabled: !busy,
          onChoose: () async {
            final dir = await getDirectoryPath();
            if (dir == null) return;
            parentPath.value = dir;
            parentController.text = dir;
          },
        ),
        kVSpacer10,
        const WorkspaceFieldLabel(label: kLabelWorkspaceNameOptional),
        kVSpacer5,
        ADOutlinedTextField(
          keyId: 'workspace-new-name',
          controller: nameController,
          isDense: true,
          enabled: !busy,
        ),
        kVSpacer5,
        Text(
          kHintWorkspaceNameOptional,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (workspaceName.isNotEmpty &&
            !isValidWorkspaceFolderName(workspaceName)) ...[
          kVSpacer5,
          const WorkspaceInlineMessage(message: kMsgWorkspaceFolderNameInvalid),
        ],
        if (pathExists.value == true) ...[
          kVSpacer5,
          const WorkspaceInlineMessage(message: kMsgWorkspaceFolderExists),
        ],
        kVSpacer10,
        WorkspacePathPreview(
          label: kMsgWorkspacePathPreview,
          path: finalPath,
        ),
        kVSpacer40,
        WorkspaceFlowActions(
          busy: busy,
          canSubmit: canSubmit && finalPath != null,
          submitLabel: kLabelWorkspaceCreate,
          onSubmit:
              finalPath != null ? () => onSubmit(finalPath) : null,
          onCancel: onBack,
          showCancel: true,
        ),
      ],
    );
  }
}

class WorkspaceCloneFlow extends HookWidget {
  const WorkspaceCloneFlow({
    super.key,
    required this.busy,
    required this.onBack,
    required this.onSubmit,
    this.gitService,
  });

  final bool busy;
  final VoidCallback onBack;
  final Future<void> Function(
    String remoteUrl,
    String parentDirectory,
    String folderName,
  ) onSubmit;
  final GitService? gitService;

  @override
  Widget build(BuildContext context) {
    final parentPath = useState<String?>(null);
    final parentController = useTextEditingController();
    final urlController = useTextEditingController();
    final urlCheckState = useState(CloneUrlCheckState.idle);
    final gitInstalled = useState<bool?>(null);
    final checkGeneration = useRef(0);
    final isMounted = useRef(true);

    useListenable(urlController);

    final git = gitService ?? GitService();

    useEffect(() {
      isMounted.value = true;
      return () {
        isMounted.value = false;
      };
    }, const []);

    useEffect(() {
      final url = urlController.text.trim();
      if (url.isEmpty) {
        urlCheckState.value = CloneUrlCheckState.idle;
        gitInstalled.value = null;
        return null;
      }

      final generation = ++checkGeneration.value;

      Future<void> runChecks() async {
        if (gitInstalled.value == null) {
          final installed = await git.isGitInstalled();
          if (generation != checkGeneration.value || !isMounted.value) return;
          gitInstalled.value = installed;
          if (!installed) return;
        } else if (gitInstalled.value == false) {
          return;
        }

        if (!looksLikeGitRemoteUrl(url)) {
          urlCheckState.value = CloneUrlCheckState.invalid;
          return;
        }

        urlCheckState.value = CloneUrlCheckState.checking;
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (generation != checkGeneration.value || !isMounted.value) return;

        final ok = await git.validateCloneUrl(url);
        if (generation != checkGeneration.value || !isMounted.value) return;
        urlCheckState.value =
            ok ? CloneUrlCheckState.valid : CloneUrlCheckState.invalid;
      }

      unawaited(runChecks());

      return () {
        if (generation == checkGeneration.value) {
          checkGeneration.value++;
        }
      };
    }, [urlController.text]);

    final url = urlController.text.trim();
    final folderName =
        url.isNotEmpty ? repoNameFromCloneUrl(url) : '';
    final clonePath = parentPath.value != null && folderName.isNotEmpty
        ? p.join(parentPath.value!, folderName)
        : null;

    final pathExists = useState<bool?>(null);
    useEffect(() {
      if (clonePath == null) {
        pathExists.value = null;
        return null;
      }
      var cancelled = false;
      Future<void>(() async {
        final exists = await Directory(clonePath).exists();
        if (!cancelled) pathExists.value = exists;
      });
      return () {
        cancelled = true;
      };
    }, [clonePath]);

    final cloneReady = url.isNotEmpty &&
        gitInstalled.value == true &&
        urlCheckState.value == CloneUrlCheckState.valid;
    final canSubmit = !busy &&
        cloneReady &&
        parentPath.value != null &&
        isValidWorkspaceFolderName(folderName) &&
        pathExists.value != true;

    return _FlowScaffold(
      action: WorkspaceSelectorAction.clone,
      children: [
        const WorkspaceFieldLabel(label: kLabelWorkspaceRepositoryUrl),
        kVSpacer5,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ADOutlinedTextField(
                keyId: 'workspace-clone-url',
                controller: urlController,
                hintText: 'https://github.com/user/repo.git',
                isDense: true,
                enabled: !busy,
              ),
            ),
            kHSpacer8,
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: WorkspaceCloneUrlStatusIcon(state: urlCheckState.value),
            ),
          ],
        ),
        if (url.isNotEmpty &&
            urlCheckState.value == CloneUrlCheckState.invalid &&
            looksLikeGitRemoteUrl(url)) ...[
          kVSpacer5,
          const WorkspaceInlineMessage(message: kMsgWorkspaceUrlNotApidash),
        ],
        if (gitInstalled.value == false) ...[
          kVSpacer10,
          const WorkspaceGitNotInstalledNotice(),
        ],
        kVSpacer10,
        const WorkspaceFieldLabel(label: kLabelWorkspaceParentFolder),
        kVSpacer5,
        WorkspaceFolderPickerRow(
          controller: parentController,
          enabled: !busy,
          onChoose: () async {
            final dir = await getDirectoryPath();
            if (dir == null) return;
            parentPath.value = dir;
            parentController.text = dir;
          },
        ),
        kVSpacer10,
        WorkspacePathPreview(
          label: kMsgWorkspaceClonePathPreview,
          path: clonePath,
        ),
        if (folderName.isNotEmpty &&
            !isValidWorkspaceFolderName(folderName)) ...[
          kVSpacer5,
          const WorkspaceInlineMessage(message: kMsgWorkspaceFolderNameInvalid),
        ],
        if (pathExists.value == true) ...[
          kVSpacer5,
          const WorkspaceInlineMessage(message: kMsgWorkspaceFolderExists),
        ],
        kVSpacer40,
        WorkspaceFlowActions(
          busy: busy,
          canSubmit: canSubmit && parentPath.value != null,
          submitLabel: kLabelWorkspaceCloneRepo,
          onSubmit: parentPath.value != null
              ? () => onSubmit(url, parentPath.value!, folderName)
              : null,
          onCancel: onBack,
          showCancel: true,
        ),
      ],
    );
  }
}

class WorkspaceOpenFlow extends HookWidget {
  const WorkspaceOpenFlow({
    super.key,
    required this.busy,
    required this.onBack,
    required this.onSubmit,
  });

  final bool busy;
  final VoidCallback onBack;
  final Future<void> Function(String path) onSubmit;

  @override
  Widget build(BuildContext context) {
    final selectedPath = useState<String?>(null);
    final pathController = useTextEditingController();
    final validation = useState<WorkspaceValidationResult?>(null);
    final validating = useState(false);

    useEffect(() {
      final path = selectedPath.value;
      if (path == null) {
        validation.value = null;
        return null;
      }
      validating.value = true;
      var cancelled = false;
      Future<void>(() async {
        final result = await validateLocalApidashWorkspace(path);
        if (!cancelled) {
          validation.value = result;
          validating.value = false;
        }
      });
      return () {
        cancelled = true;
      };
    }, [selectedPath.value]);

    final isValid = validation.value?.isValid == true;
    final canSubmit = !busy && selectedPath.value != null && isValid;

    String? errorMessage;
    final result = validation.value;
    if (result != null && !validating.value && !isValid) {
      switch (result.status) {
        case WorkspaceValidationStatus.valid:
          break;
        case WorkspaceValidationStatus.missingFolder:
          errorMessage = kMsgWorkspaceRecentMissing;
        case WorkspaceValidationStatus.notApidashWorkspace:
        case WorkspaceValidationStatus.invalidFormat:
          errorMessage = kMsgWorkspaceNotApidash;
        case WorkspaceValidationStatus.unreadable:
          errorMessage = kMsgWorkspaceOpenFailed;
      }
    }

    return _FlowScaffold(
      action: WorkspaceSelectorAction.open,
      children: [
        const WorkspaceFieldLabel(label: kLabelWorkspaceLocation),
        kVSpacer5,
        WorkspaceFolderPickerRow(
          controller: pathController,
          enabled: !busy,
          onChoose: () async {
            final dir = await getDirectoryPath();
            if (dir == null) return;
            selectedPath.value = dir;
            pathController.text = dir;
          },
        ),
        if (validating.value) ...[
          kVSpacer10,
          const LinearProgressIndicator(),
        ],
        if (errorMessage != null) ...[
          kVSpacer5,
          WorkspaceInlineMessage(message: errorMessage),
        ],
        if (isValid) ...[
          kVSpacer5,
          const WorkspaceInlineMessage(
            message: kMsgWorkspaceValidDetected,
            isError: false,
          ),
        ],
        kVSpacer40,
        WorkspaceFlowActions(
          busy: busy,
          canSubmit: canSubmit,
          submitLabel: kLabelWorkspaceOpenExisting,
          onSubmit: selectedPath.value != null
              ? () => onSubmit(selectedPath.value!)
              : null,
          onCancel: onBack,
          showCancel: true,
        ),
      ],
    );
  }
}

class _FlowScaffold extends StatelessWidget {
  const _FlowScaffold({
    required this.action,
    required this.children,
  });

  final WorkspaceSelectorAction action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceFlowHeader(
          title: workspaceActionTitle(action),
          subtitle: workspaceActionSubtitle(action),
        ),
        kVSpacer20,
        ...children,
      ],
    );
  }
}
