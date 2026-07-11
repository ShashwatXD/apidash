import 'package:apidash/consts.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/widgets/workflow_canvas.dart';
import 'package:apidash/workflow/widgets/workflow_inspector.dart';
import 'package:apidash/workflow/widgets/workflow_request_step_editor.dart';
import 'package:apidash/workflow/widgets/workflow_run_timeline.dart';
import 'package:apidash/workflow/widgets/workflow_selector_dropdown.dart';
import 'package:apidash/screens/common_widgets/environment_dropdown.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_split_view/multi_split_view.dart';

class WorkflowPage extends ConsumerStatefulWidget {
  const WorkflowPage({super.key});

  @override
  ConsumerState<WorkflowPage> createState() => _WorkflowPageState();
}

class _WorkflowPageState extends ConsumerState<WorkflowPage> {
  final MultiSplitViewController _mainController = MultiSplitViewController(
    areas: [
      Area(id: 'canvas', min: 420),
      Area(id: 'inspector', size: 320, min: 280, max: 420),
    ],
  );

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

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final catalog = ref.read(collectionCatalogProvider);
    if (catalog == null || catalog.isEmpty) {
      return;
    }

    final selection = await showDialog<({String collectionId, String requestId})>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(kLabelImportFromCollection),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView(
              children: [
                for (final entry in catalog.entries)
                  ExpansionTile(
                    title: Text(entry.value.name),
                    children: [
                      for (final summary in entry.value.requests)
                        ListTile(
                          title: Text(summary.name),
                          subtitle: Text(summary.url),
                          onTap: () => Navigator.of(context).pop(
                            (
                              collectionId: entry.key,
                              requestId: summary.id,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(kLabelCancel),
            ),
          ],
        );
      },
    );

    if (selection == null) {
      return;
    }
    await ref.read(activeWorkflowProvider.notifier).importRequestFromCollection(
          collectionId: selection.collectionId,
          requestId: selection.requestId,
        );
  }

  bool _showInspectorFor(String? selectedNodeId, WorkflowDocument? workflow) {
    if (selectedNodeId == null || workflow == null) {
      return false;
    }
    for (final node in workflow.graph.nodes) {
      if (node.id == selectedNodeId) {
        return node.type != WorkflowNodeType.request;
      }
    }
    return false;
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
    final showInspector = _showInspectorFor(selectedNodeId, workflow);

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
                if (!context.isMediumWindow) ...[
                  OutlinedButton.icon(
                    onPressed: workflow == null
                        ? null
                        : () => _showImportDialog(context),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text(kLabelImportFromCollection),
                  ),
                  kHSpacer8,
                ],
                OutlinedButton.icon(
                  onPressed: workflow == null
                      ? null
                      : () async {
                          await ref
                              .read(activeWorkflowProvider.notifier)
                              .addRequestStep();
                        },
                  icon: const Icon(Icons.add_link_rounded),
                  label: Text(
                    context.isMediumWindow
                        ? 'Add step'
                        : kLabelAddWorkflowStep,
                  ),
                ),
                if (selectedNode?.type == WorkflowNodeType.request) ...[
                  kHSpacer8,
                  FilledButton.tonalIcon(
                    onPressed: () => showWorkflowRequestStepEditor(
                      context,
                      ref,
                      node: selectedNode!,
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(
                      context.isMediumWindow ? 'Edit' : kLabelEditWorkflowStep,
                    ),
                  ),
                ],
                const Spacer(),
                const EnvironmentDropdown(),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: context.isMediumWindow
                ? Column(
                    children: [
                      Expanded(
                        flex: showInspector ? 2 : 1,
                        child: const ClipRect(child: WorkflowCanvas()),
                      ),
                      if (showInspector) ...[
                        const Divider(height: 1),
                        const Expanded(child: WorkflowInspector()),
                      ],
                    ],
                  )
                : showInspector
                    ? MultiSplitViewTheme(
                        data: MultiSplitViewThemeData(
                          dividerThickness: 3,
                          dividerPainter: DividerPainters.background(
                            color:
                                Theme.of(context).colorScheme.surfaceContainer,
                            highlightedColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            animationEnabled: false,
                          ),
                        ),
                        child: MultiSplitView(
                          controller: _mainController,
                          builder: (context, area) {
                            return switch (area.id) {
                              'inspector' => const WorkflowInspector(),
                              _ => const ClipRect(child: WorkflowCanvas()),
                            };
                          },
                        ),
                      )
                    : const ClipRect(child: WorkflowCanvas()),
          ),
          const WorkflowRunTimeline(),
      ],
    );
  }
}
