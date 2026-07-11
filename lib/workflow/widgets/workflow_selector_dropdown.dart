import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowSelectorDropdown extends ConsumerWidget {
  const WorkflowSelectorDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowsAsync = ref.watch(workflowCatalogProvider);
    final selectedId = ref.watch(selectedWorkflowIdStateProvider);

    return workflowsAsync.when(
      loading: () => const SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Text(error.toString()),
      data: (workflows) {
        if (workflows.isEmpty) {
          return OutlinedButton.icon(
            onPressed: () async {
              await ref.read(workflowCatalogProvider.notifier).createWorkflow();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New workflow'),
          );
        }

        WorkflowSummary? selected;
        for (final workflow in workflows) {
          if (workflow.id == selectedId) {
            selected = workflow;
            break;
          }
        }

        return DropdownButtonFormField<String>(
          isExpanded: true,
          value: selected?.id ?? workflows.first.id,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(),
          ),
          items: [
            for (final workflow in workflows)
              DropdownMenuItem(
                value: workflow.id,
                child: Text(
                  workflow.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const DropdownMenuItem(
              value: '__new__',
              child: Row(
                children: [
                  Icon(Icons.add, size: 18),
                  SizedBox(width: 8),
                  Text('New workflow'),
                ],
              ),
            ),
          ],
          onChanged: (value) async {
            if (value == null) {
              return;
            }
            if (value == '__new__') {
              await ref.read(workflowCatalogProvider.notifier).createWorkflow();
              return;
            }
            ref.read(selectedWorkflowIdStateProvider.notifier).state = value;
            await ref.read(activeWorkflowProvider.notifier).load(value);
          },
        );
      },
    );
  }
}
