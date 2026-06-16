import 'package:apidash/consts.dart';
import 'package:apidash/git/git_consts.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CollaborationSetupGuide extends StatelessWidget {
  const CollaborationSetupGuide({
    super.key,
    required this.status,
    required this.busy,
    this.onInitialize,
    this.onConnectRemote,
  });

  final GitStatus status;
  final bool busy;
  final VoidCallback? onInitialize;
  final VoidCallback? onConnectRemote;

  int get _activeStep {
    if (!status.gitInstalled) return 0;
    if (!status.isRepository) return 1;
    if (status.remoteUrl == null) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = _activeStep;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: kPh20,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.cloud_sync,
                size: 48,
                color: scheme.primary,
              ),
              kVSpacer16,
              Text(
                kLabelCollaborationSetupTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              kVSpacer8,
              Text(
                kMsgCollaborationSetupSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              kVSpacer20,
              _SetupStep(
                index: 1,
                title: kLabelGitSetupStepInstall,
                body: kMsgGitSetupInstallBody,
                isComplete: status.gitInstalled,
                isActive: step == 0,
                actionLabel: 'Download Git',
                onAction: step == 0
                    ? () => launchUrl(Uri.parse(kGitInstallUrl))
                    : null,
                busy: false,
              ),
              _SetupStep(
                index: 2,
                title: kLabelGitSetupStepInit,
                body: kMsgGitSetupInitBody,
                isComplete: status.isRepository,
                isActive: step == 1,
                actionLabel: kLabelInitializeRepository,
                onAction: step == 1 ? onInitialize : null,
                busy: busy && step == 1,
              ),
              _SetupStep(
                index: 3,
                title: kLabelGitSetupStepRemote,
                body: kMsgGitSetupRemoteBody,
                isComplete: status.remoteUrl != null,
                isActive: step == 2,
                actionLabel: kLabelConnectRemoteUrl,
                onAction: step == 2 ? onConnectRemote : null,
                busy: busy && step == 2,
              ),
              if (status.remoteUrl != null) ...[
                kVSpacer8,
                _SetupStep(
                  index: 4,
                  title: kLabelGitSetupStepSync,
                  body: kMsgGitSetupSyncBody,
                  isComplete: status.recentCommits.isNotEmpty,
                  isActive: step == 3,
                  actionLabel: null,
                  onAction: null,
                  busy: false,
                ),
                kVSpacer10,
                Text(
                  status.remoteUrl!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.index,
    required this.title,
    required this.body,
    required this.isComplete,
    required this.isActive,
    required this.busy,
    this.actionLabel,
    this.onAction,
  });

  final int index;
  final String title;
  final String body;
  final bool isComplete;
  final bool isActive;
  final bool busy;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = isActive
        ? scheme.primary
        : isComplete
            ? scheme.outline.withValues(alpha: 0.3)
            : scheme.outline.withValues(alpha: 0.15);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        color: isActive
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: kBorderRadius12,
          side: BorderSide(color: borderColor),
        ),
        child: Padding(
          padding: kP12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StepIndicator(
                    index: index,
                    isComplete: isComplete,
                    isActive: isActive,
                  ),
                  kHSpacer10,
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              if (isActive || isComplete) ...[
                kVSpacer10,
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (isActive && actionLabel != null && onAction != null) ...[
                  kVSpacer10,
                  FilledButton(
                    onPressed: busy ? null : onAction,
                    child: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(actionLabel!),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.index,
    required this.isComplete,
    required this.isActive,
  });

  final int index;
  final bool isComplete;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isComplete) {
      return CircleAvatar(
        radius: 14,
        backgroundColor: Colors.green,
        child: const Icon(Icons.check, size: 16, color: Colors.white),
      );
    }
    return CircleAvatar(
      radius: 14,
      backgroundColor: isActive ? scheme.primary : scheme.surfaceContainerHighest,
      child: Text(
        '$index',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isActive ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
