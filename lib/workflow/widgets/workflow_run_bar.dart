import 'package:apidash/workflow/consts.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:apidash/workflow/widgets/workflow_add_node_sheet.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowRunBar extends ConsumerWidget {
  const WorkflowRunBar({
    super.key,
    this.bottomPadding = 16,
  });

  final double bottomPadding;

  Future<void> _runWorkflow(BuildContext context, WidgetRef ref) async {
    final result = await runActiveWorkflow(ref);
    if (!context.mounted || result == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (result.success) {
      messenger.showSnackBar(getSnackBar(kMsgWorkflowRunSuccess));
      return;
    }
    messenger.showSnackBar(
      getSnackBar(
        result.error ?? kMsgWorkflowRunFailed,
        color: kColorRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final workflow = ref.watch(activeWorkflowProvider);
    final running = ref.watch(workflowRunInProgressProvider);

    if (workflow == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        elevation: 2,
        shadowColor: theme.shadowColor.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.25),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonalIcon(
                onPressed: running
                    ? null
                    : () => showWorkflowAddNodeSheet(context, ref),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(kLabelAddWorkflowNode),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: kTooltipAutoArrange,
                child: FilledButton.tonalIcon(
                  onPressed: running
                      ? null
                      : () => ref
                          .read(activeWorkflowProvider.notifier)
                          .autoArrangeGraph(),
                  icon: const Icon(Icons.account_tree_outlined, size: 20),
                  label: Text(
                    context.isMediumWindow ? 'Arrange' : kLabelAutoArrange,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: running ? null : () => _runWorkflow(context, ref),
                icon: running
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(
                  running ? 'Running…' : kLabelRunWorkflow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
