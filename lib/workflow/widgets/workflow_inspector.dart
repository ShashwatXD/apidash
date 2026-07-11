import 'package:apidash/consts.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:apidash/workflow/providers/workflow_ui_providers.dart';
import 'package:apidash/workflow/widgets/workflow_request_step_editor.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowInspector extends ConsumerWidget {
  const WorkflowInspector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflow = ref.watch(activeWorkflowProvider);
    final selectedNodeId = ref.watch(selectedWorkflowNodeIdProvider);
    if (workflow == null || selectedNodeId == null) {
      return const Center(child: Text('Select a node'));
    }

    final node = workflow.graph.nodes
        .where((candidate) => candidate.id == selectedNodeId)
        .cast<WorkflowGraphNode?>()
        .firstWhere((candidate) => candidate != null, orElse: () => null);
    if (node == null) {
      return const Center(child: Text('Node not found'));
    }

    if (node.type == WorkflowNodeType.request) {
      return Center(
        child: Padding(
          padding: kP12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                kMsgWorkflowDoubleClickEdit,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              kVSpacer16,
              FilledButton.icon(
                onPressed: () =>
                    showWorkflowRequestStepEditor(context, ref, node: node),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text(kLabelEditWorkflowStep),
              ),
              kVSpacer16,
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete step'),
                      content: const Text(
                        'Remove this request step from the workflow?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text(kLabelCancel),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text(kTooltipDelete),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) {
                    return;
                  }
                  await ref
                      .read(activeWorkflowProvider.notifier)
                      .deleteNode(node.id);
                  ref.read(selectedWorkflowNodeIdProvider.notifier).state =
                      null;
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete step'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: kP12,
      children: [
        Text('Inspector', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (node.type == WorkflowNodeType.condition) ...[
          Text(
            'Condition expression',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          kVSpacer8,
          Text(
            node.conditionExpression?.isNotEmpty == true
                ? node.conditionExpression!
                : 'Use expressions like status>=200&&status<300 in a future update.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (node.type == WorkflowNodeType.manualStart) ...[
          Text(
            'Manual start node — connect Next to the first request step.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        kVSpacer16,
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(activeWorkflowProvider.notifier).deleteNode(node.id);
            ref.read(selectedWorkflowNodeIdProvider.notifier).state = null;
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete node'),
        ),
      ],
    );
  }
}
