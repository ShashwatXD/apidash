import 'package:apidash/consts.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:apidash/workflow/providers/workflow_ui_providers.dart';
import 'package:apidash/workflow/widgets/workflow_request_step_editor.dart';
import 'package:apidash/workflow/widgets/workflow_variable_browser.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_split_view/multi_split_view.dart';

Future<void> openWorkflowNodeEditor(
  BuildContext context,
  WidgetRef ref, {
  required WorkflowGraphNode node,
}) {
  return switch (node.type) {
    WorkflowNodeType.request =>
      showWorkflowRequestStepEditor(context, ref, node: node),
    WorkflowNodeType.loop =>
      showWorkflowLoopStepEditor(context, ref, node: node),
    WorkflowNodeType.condition =>
      showWorkflowConditionStepEditor(context, ref, node: node),
    _ => Future.value(),
  };
}

Future<void> showWorkflowLoopStepEditor(
  BuildContext context,
  WidgetRef ref, {
  required WorkflowGraphNode node,
}) {
  return _showLogicNodeEditor(
    context,
    node: node,
    editor: _WorkflowLoopStepEditorPage(node: node),
  );
}

Future<void> showWorkflowConditionStepEditor(
  BuildContext context,
  WidgetRef ref, {
  required WorkflowGraphNode node,
}) {
  return _showLogicNodeEditor(
    context,
    node: node,
    editor: _WorkflowConditionStepEditorPage(node: node),
  );
}

Future<void> _showLogicNodeEditor(
  BuildContext context, {
  required WorkflowGraphNode node,
  required Widget editor,
}) {
  if (context.isMediumWindow) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (dialogContext) => editor,
      ),
    );
  }

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 1280,
        height: 820,
        child: editor,
      ),
    ),
  );
}

class _WorkflowLoopStepEditorPage extends ConsumerStatefulWidget {
  const _WorkflowLoopStepEditorPage({required this.node});

  final WorkflowGraphNode node;

  @override
  ConsumerState<_WorkflowLoopStepEditorPage> createState() =>
      _WorkflowLoopStepEditorPageState();
}

class _WorkflowLoopStepEditorPageState
    extends ConsumerState<_WorkflowLoopStepEditorPage> {
  late final TextEditingController _labelController;
  late final TextEditingController _listVarController;
  late final TextEditingController _iterationsController;
  late WorkflowLoopMode _loopMode;
  final MultiSplitViewController _splitController = MultiSplitViewController(
    areas: [
      Area(id: 'variables', size: 260, min: 200, max: 360),
      Area(id: 'config', min: 420),
      Area(id: 'guide', size: 360, min: 280, max: 520),
    ],
  );

  @override
  void initState() {
    super.initState();
    final loopExpr = widget.node.loopExpression ?? 'var:items';
    final listVar = loopExpr.startsWith('var:')
        ? loopExpr.substring(4).trim()
        : 'items';
    _labelController = TextEditingController(
      text: widget.node.label.isNotEmpty ? widget.node.label : kLabelWorkflowLoop,
    );
    _listVarController = TextEditingController(text: listVar);
    _loopMode = widget.node.loopMode;
    final maxIterations = widget.node.loopMaxIterations;
    _iterationsController = TextEditingController(
      text: maxIterations != null && maxIterations > 0 ? '$maxIterations' : '',
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    _listVarController.dispose();
    _iterationsController.dispose();
    _splitController.dispose();
    super.dispose();
  }

  WorkflowGraphNode? _currentNode(WorkflowDocument? workflow) {
    if (workflow == null) {
      return null;
    }
    for (final candidate in workflow.graph.nodes) {
      if (candidate.id == widget.node.id) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _saveAndClose() async {
    final label = _labelController.text.trim();
    final iterationsRaw = _iterationsController.text.trim();
    final parsedIterations = int.tryParse(iterationsRaw);

    if (_loopMode == WorkflowLoopMode.repeat) {
      if (parsedIterations == null || parsedIterations <= 0) {
        return;
      }
      await ref.read(activeWorkflowProvider.notifier).updateSelectedNode(
            widget.node.copyWith(
              label: label.isNotEmpty
                  ? label
                  : 'Repeat $parsedIterations times',
              loopMode: WorkflowLoopMode.repeat,
              loopMaxIterations: parsedIterations,
              clearLoopExpression: true,
            ),
          );
    } else {
      final listVar = _listVarController.text.trim();
      if (listVar.isEmpty) {
        return;
      }
      final loopMaxIterations =
          parsedIterations != null && parsedIterations > 0
              ? parsedIterations
              : null;
      await ref.read(activeWorkflowProvider.notifier).updateSelectedNode(
            widget.node.copyWith(
              label: label.isNotEmpty ? label : kLabelWorkflowLoop,
              loopMode: WorkflowLoopMode.forEach,
              loopExpression: 'var:$listVar',
              loopMaxIterations: loopMaxIterations,
              clearLoopMaxIterations: loopMaxIterations == null,
            ),
          );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete node'),
        content: const Text(
          'Remove this loop from the workflow? Connected edges will also be removed.',
        ),
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
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(activeWorkflowProvider.notifier).deleteNode(widget.node.id);
    ref.read(selectedWorkflowNodeIdProvider.notifier).state = null;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(activeWorkflowProvider);
    final node = _currentNode(workflow);
    if (workflow == null || node == null) {
      return const Scaffold(
        body: Center(child: Text(kMsgWorkflowNotFound)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.label.isNotEmpty ? node.label : kLabelWorkflowLoop,
            ),
            Text(
              'For-each loop',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: kTooltipDelete,
            onPressed: _confirmDelete,
          ),
          FilledButton(
            onPressed: _saveAndClose,
            child: const Text(kLabelDone),
          ),
          kHSpacer12,
        ],
      ),
      body: _LogicNodeEditorBody(
        nodeId: node.id,
        splitController: _splitController,
        config: _LoopConfigPanel(
          labelController: _labelController,
          listVarController: _listVarController,
          iterationsController: _iterationsController,
          loopMode: _loopMode,
          onLoopModeChanged: (mode) => setState(() => _loopMode = mode),
        ),
        guide: const _LoopGuidePanel(),
      ),
    );
  }
}

class _WorkflowConditionStepEditorPage extends ConsumerStatefulWidget {
  const _WorkflowConditionStepEditorPage({required this.node});

  final WorkflowGraphNode node;

  @override
  ConsumerState<_WorkflowConditionStepEditorPage> createState() =>
      _WorkflowConditionStepEditorPageState();
}

class _WorkflowConditionStepEditorPageState
    extends ConsumerState<_WorkflowConditionStepEditorPage> {
  late final TextEditingController _labelController;
  late final TextEditingController _expressionController;
  final MultiSplitViewController _splitController = MultiSplitViewController(
    areas: [
      Area(id: 'variables', size: 260, min: 200, max: 360),
      Area(id: 'config', min: 420),
      Area(id: 'guide', size: 360, min: 280, max: 520),
    ],
  );

  static const _expressionPresets = [
    'status>=200',
    'status<400',
    'status>=200&&status<300',
    'var:token',
    'true',
    'false',
  ];

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(
      text: widget.node.label.isNotEmpty
          ? widget.node.label
          : kLabelWorkflowCondition,
    );
    _expressionController = TextEditingController(
      text: widget.node.conditionExpression ?? 'status>=200',
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    _expressionController.dispose();
    _splitController.dispose();
    super.dispose();
  }

  WorkflowGraphNode? _currentNode(WorkflowDocument? workflow) {
    if (workflow == null) {
      return null;
    }
    for (final candidate in workflow.graph.nodes) {
      if (candidate.id == widget.node.id) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _saveAndClose() async {
    final expression = _expressionController.text.trim();
    if (expression.isEmpty) {
      return;
    }
    final label = _labelController.text.trim();
    await ref.read(activeWorkflowProvider.notifier).updateSelectedNode(
          widget.node.copyWith(
            label: label.isNotEmpty ? label : kLabelWorkflowCondition,
            conditionExpression: expression,
          ),
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete node'),
        content: const Text(
          'Remove this condition from the workflow? Connected edges will also be removed.',
        ),
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
    if (confirmed != true || !mounted) {
      return;
    }
    await ref.read(activeWorkflowProvider.notifier).deleteNode(widget.node.id);
    ref.read(selectedWorkflowNodeIdProvider.notifier).state = null;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(activeWorkflowProvider);
    final node = _currentNode(workflow);
    if (workflow == null || node == null) {
      return const Scaffold(
        body: Center(child: Text(kMsgWorkflowNotFound)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.label.isNotEmpty ? node.label : kLabelWorkflowCondition,
            ),
            Text(
              'If / else branch',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: kTooltipDelete,
            onPressed: _confirmDelete,
          ),
          FilledButton(
            onPressed: _saveAndClose,
            child: const Text(kLabelDone),
          ),
          kHSpacer12,
        ],
      ),
      body: _LogicNodeEditorBody(
        nodeId: node.id,
        splitController: _splitController,
        config: _ConditionConfigPanel(
          labelController: _labelController,
          expressionController: _expressionController,
          presets: _expressionPresets,
          onPresetSelected: (value) => setState(() {
            _expressionController.text = value;
          }),
        ),
        guide: const _ConditionGuidePanel(),
      ),
    );
  }
}

class _LogicNodeEditorBody extends StatelessWidget {
  const _LogicNodeEditorBody({
    required this.nodeId,
    required this.splitController,
    required this.config,
    required this.guide,
  });

  final String nodeId;
  final MultiSplitViewController splitController;
  final Widget config;
  final Widget guide;

  @override
  Widget build(BuildContext context) {
    if (context.isMediumWindow) {
      return DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: kLabelConfiguration),
                Tab(text: kLabelWorkflowVariables),
                Tab(text: 'Guide'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  config,
                  WorkflowVariableBrowser(nodeId: nodeId),
                  guide,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return MultiSplitViewTheme(
      data: MultiSplitViewThemeData(
        dividerThickness: 3,
        dividerPainter: DividerPainters.background(
          color: Theme.of(context).colorScheme.surfaceContainer,
          highlightedColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          animationEnabled: false,
        ),
      ),
      child: MultiSplitView(
        controller: splitController,
        builder: (context, area) {
          return switch (area.id) {
            'variables' => WorkflowVariableBrowser(nodeId: nodeId),
            'guide' => guide,
            _ => config,
          };
        },
      ),
    );
  }
}

class _LoopConfigPanel extends StatefulWidget {
  const _LoopConfigPanel({
    required this.labelController,
    required this.listVarController,
    required this.iterationsController,
    required this.loopMode,
    required this.onLoopModeChanged,
  });

  final TextEditingController labelController;
  final TextEditingController listVarController;
  final TextEditingController iterationsController;
  final WorkflowLoopMode loopMode;
  final ValueChanged<WorkflowLoopMode> onLoopModeChanged;

  @override
  State<_LoopConfigPanel> createState() => _LoopConfigPanelState();
}

class _LoopConfigPanelState extends State<_LoopConfigPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.loopMode == WorkflowLoopMode.repeat ? 1 : 2,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant _LoopConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tabCount = widget.loopMode == WorkflowLoopMode.repeat ? 1 : 2;
    if (_tabController.length != tabCount) {
      _tabController.dispose();
      _tabController = TabController(length: tabCount, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRepeat = widget.loopMode == WorkflowLoopMode.repeat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Text('Loop configuration', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SegmentedButton<WorkflowLoopMode>(
            segments: const [
              ButtonSegment(
                value: WorkflowLoopMode.forEach,
                label: Text(kLabelWorkflowLoopForEach),
                icon: Icon(Icons.list_rounded, size: 18),
              ),
              ButtonSegment(
                value: WorkflowLoopMode.repeat,
                label: Text(kLabelWorkflowLoopRepeat),
                icon: Icon(Icons.repeat_rounded, size: 18),
              ),
            ],
            selected: {widget.loopMode},
            onSelectionChanged: (selection) {
              widget.onLoopModeChanged(selection.first);
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: widget.labelController,
            decoration: const InputDecoration(
              labelText: 'Node label',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (isRepeat) ...[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextField(
                  controller: widget.iterationsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Times to repeat',
                    hintText: '5',
                    helperText:
                        'Runs the connected Each step this many times. No list variable needed.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Available references', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                const _ReferenceChip(
                  reference: '{{loop.index}}',
                  label: 'Zero-based index (0, 1, 2…)',
                ),
              ],
            ),
          ),
        ] else ...[
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: kLabelWorkflowLoopList),
              Tab(text: kLabelWorkflowLoopIterations),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    TextField(
                      controller: widget.listVarController,
                      decoration: const InputDecoration(
                        labelText: 'List variable',
                        hintText: 'items',
                        helperText:
                            'Set this under Workflow → Variables. JSON array or comma-separated values.',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixText: 'var:',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Downstream references', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    const _ReferenceChip(
                      reference: '{{loop.item}}',
                      label: 'Current item',
                    ),
                    const SizedBox(height: 8),
                    const _ReferenceChip(
                      reference: '{{loop.index}}',
                      label: 'Zero-based index',
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    TextField(
                      controller: widget.iterationsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max items (optional)',
                        hintText: 'All items',
                        helperText:
                            'Leave empty to process the full list. Set a number to cap iterations.',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConditionConfigPanel extends StatelessWidget {
  const _ConditionConfigPanel({
    required this.labelController,
    required this.expressionController,
    required this.presets,
    required this.onPresetSelected,
  });

  final TextEditingController labelController;
  final TextEditingController expressionController;
  final List<String> presets;
  final ValueChanged<String> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Condition configuration', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        TextField(
          controller: labelController,
          decoration: const InputDecoration(
            labelText: 'Node label',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: expressionController,
          decoration: const InputDecoration(
            labelText: 'Expression',
            hintText: 'status>=200',
            helperText:
                'Evaluated after the previous step. Wire True and False ports to branch.',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        Text('Quick presets', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in presets)
              ActionChip(
                label: Text(preset),
                onPressed: () => onPresetSelected(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class _LoopGuidePanel extends StatelessWidget {
  const _LoopGuidePanel();

  @override
  Widget build(BuildContext context) {
    return const _GuidePanel(
      title: 'How loops work',
      sections: [
        _GuideSection(
          title: 'Modes',
          body:
              'For each item runs once per entry in a list variable. Repeat runs the same step N times with no list setup.',
        ),
        _GuideSection(
          title: 'Wiring',
          body:
              'Connect In from the previous step. Connect Each to the first step inside the loop body. Connect Done to the step that runs after all iterations finish.',
        ),
        _GuideSection(
          title: 'List variable',
          body:
              'For each mode: set a variable under Workflow → Variables, e.g. items = ["a","b"] or comma-separated values.',
        ),
        _GuideSection(
          title: 'Per iteration',
          body:
              'Use {{loop.item}} and {{loop.index}} in downstream request URLs, headers, or bodies.',
        ),
      ],
    );
  }
}

class _ConditionGuidePanel extends StatelessWidget {
  const _ConditionGuidePanel();

  @override
  Widget build(BuildContext context) {
    return const _GuidePanel(
      title: 'How conditions work',
      sections: [
        _GuideSection(
          title: 'Wiring',
          body:
              'Connect In after a request step. Wire True to the success path and False to the alternate path.',
        ),
        _GuideSection(
          title: 'Status checks',
          body:
              'Use status>=200, status<400, or status>=200&&status<300 to branch on the last HTTP response code.',
        ),
        _GuideSection(
          title: 'Variables',
          body:
              'Use var:token to branch when a flow variable is set and non-empty.',
        ),
      ],
    );
  }
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel({
    required this.title,
    required this.sections,
  });

  final String title;
  final List<_GuideSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        for (final section in sections) ...[
          Text(section.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            section.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _GuideSection {
  const _GuideSection({required this.title, required this.body});

  final String title;
  final String body;
}

class _ReferenceChip extends StatelessWidget {
  const _ReferenceChip({
    required this.reference,
    required this.label,
  });

  final String reference;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: theme.textTheme.bodyMedium),
      subtitle: Text(reference, style: theme.textTheme.labelLarge),
    );
  }
}
