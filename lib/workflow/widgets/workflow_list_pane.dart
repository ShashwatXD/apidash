import 'package:apidash/consts.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/screens/common_widgets/common_widgets.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowListPane extends ConsumerWidget {
  const WorkflowListPane({
    super.key,
    this.onWorkflowSelected,
  });

  final VoidCallback? onWorkflowSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowsAsync = ref.watch(workflowCatalogProvider);
    final selectedId = ref.watch(selectedWorkflowIdStateProvider);
    final filter = ref.watch(workflowSearchQueryProvider).trim().toLowerCase();

    return Padding(
      padding:
          (!context.isMediumWindow && kIsMacOS ? kPt24l4 : kPt8l4) +
          (context.isMediumWindow ? kPb70 : EdgeInsets.zero),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kLabelWorkflows,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  await ref
                      .read(workflowCatalogProvider.notifier)
                      .createWorkflow();
                },
                style: kButtonSidebarStyle,
                child: const Text(kLabelPlusNew, style: kTextStyleButton),
              ),
            ],
          ),
          kVSpacer10,
          SidebarFilter(
            filterHintText: kHintFilterWorkflows,
            onFilterFieldChanged: (value) {
              ref.read(workflowSearchQueryProvider.notifier).state =
                  value.toLowerCase();
            },
          ),
          kVSpacer10,
          Expanded(
            child: workflowsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text(error.toString())),
              data: (workflows) {
                final filtered = workflows
                    .where(
                      (workflow) =>
                          filter.isEmpty ||
                          workflow.name.toLowerCase().contains(filter),
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      filter.isEmpty
                          ? 'Create your first workflow'
                          : 'No workflows match your filter',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final workflow = filtered[index];
                    final selected = workflow.id == selectedId;
                    return ListTile(
                      selected: selected,
                      title: Text(
                        workflow.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${workflow.stepCount} step${workflow.stepCount == 1 ? '' : 's'}',
                      ),
                      onTap: () async {
                        ref
                            .read(selectedWorkflowIdStateProvider.notifier)
                            .state = workflow.id;
                        await ref
                            .read(activeWorkflowProvider.notifier)
                            .load(workflow.id);
                        onWorkflowSelected?.call();
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
