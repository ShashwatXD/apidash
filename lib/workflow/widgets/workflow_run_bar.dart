import 'package:apidash/consts.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowRunBar extends ConsumerWidget {
  const WorkflowRunBar({
    super.key,
    this.bottomPadding = 16,
  });

  final double bottomPadding;

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
          child: FilledButton.icon(
            onPressed: running ? null : () => runActiveWorkflow(ref),
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
        ),
      ),
    );
  }
}
