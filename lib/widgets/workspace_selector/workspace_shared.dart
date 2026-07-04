import 'package:apidash/consts.dart';
import 'package:apidash/git/consts.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WorkspaceFolderPickerRow extends StatelessWidget {
  const WorkspaceFolderPickerRow({
    super.key,
    required this.controller,
    required this.onChoose,
    required this.enabled,
  });

  final TextEditingController controller;
  final Future<void> Function() onChoose;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ADOutlinedTextField(
            keyId: 'workspace-folder-path',
            controller: controller,
            textStyle: kTextStyleButtonSmall,
            readOnly: true,
            isDense: true,
            maxLines: null,
          ),
        ),
        kHSpacer10,
        FilledButton.tonalIcon(
          onPressed: enabled ? onChoose : null,
          label: const Text(kLabelSelect),
          icon: const Icon(Icons.folder_rounded),
        ),
      ],
    );
  }
}

class WorkspaceInlineMessage extends StatelessWidget {
  const WorkspaceInlineMessage({
    super.key,
    required this.message,
    this.isError = true,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isError ? scheme.error : scheme.onSurfaceVariant,
          ),
    );
  }
}

class WorkspaceGitNotInstalledNotice extends StatelessWidget {
  const WorkspaceGitNotInstalledNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
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
          child: const Text(kLabelGitSetupStepInstall),
        ),
      ],
    );
  }
}

enum CloneUrlCheckState { idle, checking, valid, invalid }

class WorkspaceCloneUrlStatusIcon extends StatelessWidget {
  const WorkspaceCloneUrlStatusIcon({super.key, required this.state});

  final CloneUrlCheckState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: switch (state) {
        CloneUrlCheckState.idle => const SizedBox.shrink(),
        CloneUrlCheckState.checking => const Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        CloneUrlCheckState.valid => Icon(
            Icons.check_circle,
            size: 20,
            color: kColorStatusCode200,
          ),
        CloneUrlCheckState.invalid => Icon(
            Icons.cancel,
            size: 20,
            color: Theme.of(context).colorScheme.error,
          ),
      },
    );
  }
}

class WorkspaceFieldLabel extends StatelessWidget {
  const WorkspaceFieldLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: kCodeStyle.copyWith(
        fontSize: 12,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class WorkspaceFlowActions extends StatelessWidget {
  const WorkspaceFlowActions({
    super.key,
    required this.busy,
    required this.canSubmit,
    required this.submitLabel,
    required this.onSubmit,
    this.onCancel,
    this.showCancel = false,
  });

  final bool busy;
  final bool canSubmit;
  final String submitLabel;
  final VoidCallback? onSubmit;
  final VoidCallback? onCancel;
  final bool showCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: canSubmit && !busy ? onSubmit : null,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(submitLabel),
          ),
          if (showCancel && onCancel != null) ...[
            kHSpacer8,
            TextButton(
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
          ],
        ],
      ),
    );
  }
}
