import 'dart:async';

import 'package:apidash/consts.dart';
import 'package:apidash/git/consts.dart';
import 'package:apidash/git/git_error.dart';
import 'package:apidash/git/services/git_service.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

enum _CloneUrlCheckState { idle, checking, valid, invalid }

class WorkspaceSelector extends HookWidget {
  const WorkspaceSelector({
    super.key,
    required this.onContinue,
    this.onClone,
    this.onCancel,
    this.gitService,
  });

  final Future<void> Function(String path)? onContinue;
  final Future<void> Function(
    String remoteUrl,
    String parentDirectory,
  )? onClone;
  final Future<void> Function()? onCancel;
  final GitService? gitService;

  @override
  Widget build(BuildContext context) {
    final busy = useState(false);
    final isMounted = useRef(true);
    useEffect(() {
      isMounted.value = true;
      return () {
        isMounted.value = false;
      };
    }, const []);
    final selectedDirectory = useState<String?>(null);
    final selectedDirectoryTextController = useTextEditingController();
    final workspaceName = useState<String?>(null);
    final remoteUrlController = useTextEditingController();
    final urlCheckState = useState(_CloneUrlCheckState.idle);
    final checkGeneration = useRef(0);
    final gitInstalled = useState<bool?>(null);
    useListenable(remoteUrlController);

    final git = gitService ?? GitService();

    useEffect(() {
      final url = remoteUrlController.text.trim();
      if (url.isEmpty) {
        urlCheckState.value = _CloneUrlCheckState.idle;
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
          urlCheckState.value = _CloneUrlCheckState.invalid;
          return;
        }

        urlCheckState.value = _CloneUrlCheckState.checking;
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (generation != checkGeneration.value || !isMounted.value) return;

        final ok = await git.validateCloneUrl(url);
        if (generation != checkGeneration.value || !isMounted.value) return;
        urlCheckState.value =
            ok ? _CloneUrlCheckState.valid : _CloneUrlCheckState.invalid;
      }

      unawaited(runChecks());

      return () {
        if (generation == checkGeneration.value) {
          checkGeneration.value++;
        }
      };
    }, [remoteUrlController.text]);

    final cloneUrl = remoteUrlController.text.trim();
    final cloneAttempt = cloneUrl.isNotEmpty;
    final cloneReady = !cloneAttempt ||
        (gitInstalled.value == true &&
            urlCheckState.value == _CloneUrlCheckState.valid);
    final canContinue =
        !busy.value && selectedDirectory.value != null && cloneReady;

    Future<void> submit() async {
      if (!canContinue || selectedDirectory.value == null) return;
      busy.value = true;
      try {
        if (cloneAttempt &&
            gitInstalled.value == true &&
            urlCheckState.value == _CloneUrlCheckState.valid) {
          await onClone?.call(cloneUrl, selectedDirectory.value!);
        } else {
          var finalPath = selectedDirectory.value!;
          if (workspaceName.value != null &&
              workspaceName.value!.trim().isNotEmpty) {
            finalPath = p.join(finalPath, workspaceName.value);
          }
          await onContinue?.call(finalPath);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            getSnackBar(formatGitCollaborationError(e), color: kColorRed),
          );
        }
      } finally {
        if (isMounted.value) {
          busy.value = false;
        }
      }
    }

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                kMsgSelectWorkspace,
                style: kTextStyleButton,
              ),
              kVSpacer20,
              Row(
                children: [
                  Text(
                    'CHOOSE DIRECTORY',
                    style: kCodeStyle.copyWith(fontSize: 12),
                  ),
                ],
              ),
              kVSpacer5,
              Row(
                children: [
                  Expanded(
                    child: ADOutlinedTextField(
                      keyId: 'workspace-path',
                      controller: selectedDirectoryTextController,
                      textStyle: kTextStyleButtonSmall,
                      readOnly: true,
                      isDense: true,
                      maxLines: null,
                    ),
                  ),
                  kHSpacer10,
                  FilledButton.tonalIcon(
                    onPressed: busy.value
                        ? null
                        : () async {
                            selectedDirectory.value = await getDirectoryPath();
                            selectedDirectoryTextController.text =
                                selectedDirectory.value ?? '';
                          },
                    label: const Text(kLabelSelect),
                    icon: const Icon(Icons.folder_rounded),
                  ),
                ],
              ),
              kVSpacer10,
              Row(
                children: [
                  Text(
                    'WORKSPACE NAME [OPTIONAL]\n(FOLDER WILL BE CREATED IN THE SELECTED DIRECTORY)',
                    style: kCodeStyle.copyWith(fontSize: 12),
                  ),
                ],
              ),
              kVSpacer5,
              ADOutlinedTextField(
                keyId: 'workspace-name',
                onChanged: (value) {
                  workspaceName.value = value.trim();
                },
                isDense: true,
                enabled: !cloneAttempt,
              ),
              kVSpacer10,
              Row(
                children: [
                  Text(
                    kLabelCloneFromGitOptional,
                    style: kCodeStyle.copyWith(fontSize: 12),
                  ),
                ],
              ),
              kVSpacer5,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ADOutlinedTextField(
                      keyId: 'workspace-clone-url',
                      controller: remoteUrlController,
                      hintText: 'https://github.com/user/repo.git',
                      isDense: true,
                    ),
                  ),
                  kHSpacer8,
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _CloneUrlStatusIcon(state: urlCheckState.value),
                  ),
                ],
              ),
              if (gitInstalled.value == false) ...[
                kVSpacer5,
                const _GitNotInstalledNotice(),
              ],
              kVSpacer40,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: canContinue ? submit : null,
                    child: busy.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(kLabelContinue),
                  ),
                  kHSpacer10,
                  FilledButton(
                    onPressed: busy.value ? null : onCancel,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? kColorDarkDanger
                              : kColorLightDanger,
                      surfaceTintColor: kColorRed,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: const Text(kLabelCancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GitNotInstalledNotice extends StatelessWidget {
  const _GitNotInstalledNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kMsgGitNotInstalled,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          kVSpacer5,
          TextButton(
            onPressed: () => launchUrl(Uri.parse(kGitInstallUrl)),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(kLabelGitSetupStepInstall),
          ),
        ],
      ),
    );
  }
}

class _CloneUrlStatusIcon extends StatelessWidget {
  const _CloneUrlStatusIcon({required this.state});

  final _CloneUrlCheckState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: switch (state) {
        _CloneUrlCheckState.idle => const SizedBox.shrink(),
        _CloneUrlCheckState.checking => const Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        _CloneUrlCheckState.valid => Icon(
            Icons.check_circle,
            size: 20,
            color: Colors.green.shade600,
          ),
        _CloneUrlCheckState.invalid => Icon(
            Icons.cancel,
            size: 20,
            color: Theme.of(context).colorScheme.error,
          ),
      },
    );
  }
}
