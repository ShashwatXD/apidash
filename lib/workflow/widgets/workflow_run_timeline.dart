import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowRunTimeline extends ConsumerWidget {
  const WorkflowRunTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflow = ref.watch(activeWorkflowProvider);
    final results = ref.watch(workflowNodeRunResultsProvider).values.toList();
    final running = ref.watch(workflowRunInProgressProvider);

    if (workflow == null || (results.isEmpty && !running)) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 108,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView.separated(
        padding: kPh8,
        itemCount: results.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final result = results[index];
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(
              switch (result.status) {
                WorkflowNodeRunStatus.success => Icons.check_circle_outline,
                WorkflowNodeRunStatus.failed => Icons.error_outline,
                WorkflowNodeRunStatus.running => Icons.sync,
                _ => Icons.radio_button_unchecked,
              },
              size: 18,
              color: switch (result.status) {
                WorkflowNodeRunStatus.success => Colors.green,
                WorkflowNodeRunStatus.failed =>
                  Theme.of(context).colorScheme.error,
                WorkflowNodeRunStatus.running =>
                  Theme.of(context).colorScheme.primary,
                _ => null,
              },
            ),
            title: Text(
              result.label.isEmpty ? result.nodeId : result.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            subtitle: Text(
              [
                if (result.statusCode != null) 'status ${result.statusCode}',
                if (result.durationMs != null) '${result.durationMs} ms',
                if (result.message != null) result.message,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          );
        },
      ),
    );
  }
}
