import 'package:apidash/consts.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/widgets/workflow_canvas.dart';
import 'package:apidash/workflow/widgets/workflow_flow_variables_sheet.dart';
import 'package:apidash/workflow/widgets/workflow_help_sheet.dart';
import 'package:apidash/workflow/widgets/workflow_logic_node_editor.dart';
import 'package:apidash/workflow/widgets/workflow_run_timeline.dart';
import 'package:apidash/workflow/widgets/workflow_selector_dropdown.dart';
import 'package:apidash/screens/common_widgets/environment_dropdown.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowPage extends ConsumerStatefulWidget {
  const WorkflowPage({super.key});

  @override
  ConsumerState<WorkflowPage> createState() => _WorkflowPageState();
}

class _WorkflowPageState extends ConsumerState<WorkflowPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!isWorkspaceStorageInitialized()) {
      return;
    }
    await ref.read(workflowCatalogProvider.notifier).reloadFromDisk();
    final selected = ref.read(selectedWorkflowIdStateProvider);
    if (selected != null) {
      await ref.read(activeWorkflowProvider.notifier).load(selected);
      return;
    }
    final workflows = ref.read(workflowCatalogProvider).value ?? const [];
    if (workflows.isNotEmpty) {
      ref.read(selectedWorkflowIdStateProvider.notifier).state =
          workflows.first.id;
      await ref.read(activeWorkflowProvider.notifier).load(workflows.first.id);
    }
  }

  Future<void> _confirmDeleteSelectedNode(WorkflowGraphNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete node'),
        content: Text('Remove "${node.label}" from this workflow?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(kLabelCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(kTooltipDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(activeWorkflowProvider.notifier).deleteNode(node.id);
    ref.read(selectedWorkflowNodeIdProvider.notifier).state = null;
  }

  WorkflowGraphNode? _selectedNode(
    String? selectedNodeId,
    WorkflowDocument? workflow,
  ) {
    if (selectedNodeId == null || workflow == null) {
      return null;
    }
    for (final node in workflow.graph.nodes) {
      if (node.id == selectedNodeId) {
        return node;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(activeWorkflowProvider);
    final selectedNodeId = ref.watch(selectedWorkflowNodeIdProvider);
    final selectedNode = _selectedNode(selectedNodeId, workflow);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: kP8,
          child: Row(
            children: [
              SizedBox(
                width: context.isMediumWindow ? 200 : 280,
                child: const WorkflowSelectorDropdown(),
              ),
              kHSpacer8,
              FilledButton.tonalIcon(
                onPressed: workflow == null
                    ? null
                    : () => showWorkflowFlowVariablesSheet(context, ref),
                icon: const Icon(Icons.data_object_outlined),
                label: Text(
                  context.isMediumWindow ? 'Vars' : kLabelWorkflowVariables,
                ),
              ),
              kHSpacer8,
              IconButton(
                tooltip: kLabelWorkflowHelp,
                onPressed: () => showWorkflowHelpSheet(context),
                icon: const Icon(Icons.help_outline_rounded),
              ),
              if (selectedNode != null &&
                  selectedNode.type != WorkflowNodeType.manualStart) ...[
                kHSpacer8,
                FilledButton.tonalIcon(
                  onPressed: () => openWorkflowNodeEditor(
                    context,
                    ref,
                    node: selectedNode,
                  ),
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(
                    context.isMediumWindow ? 'Edit' : 'Edit node',
                  ),
                ),
                kHSpacer8,
                IconButton(
                  tooltip: kTooltipDelete,
                  onPressed: () => _confirmDeleteSelectedNode(selectedNode),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
              const Spacer(),
              const EnvironmentDropdown(),
            ],
          ),
        ),
        const Divider(height: 1),
        const Expanded(child: ClipRect(child: WorkflowCanvas())),
        const WorkflowRunTimeline(),
      ],
    );
  }
}
