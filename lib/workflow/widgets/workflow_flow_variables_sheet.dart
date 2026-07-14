import 'package:apidash/consts.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showWorkflowFlowVariablesSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => const _WorkflowFlowVariablesSheet(),
  );
}

class _WorkflowFlowVariablesSheet extends ConsumerStatefulWidget {
  const _WorkflowFlowVariablesSheet();

  @override
  ConsumerState<_WorkflowFlowVariablesSheet> createState() =>
      _WorkflowFlowVariablesSheetState();
}

class _WorkflowFlowVariablesSheetState
    extends ConsumerState<_WorkflowFlowVariablesSheet> {
  late List<WorkflowFlowVariable> _variables;

  @override
  void initState() {
    super.initState();
    _variables = [
      for (final variable in ref.read(activeWorkflowProvider)?.flowVariables ??
          const <WorkflowFlowVariable>[])
        variable,
    ];
  }

  void _addVariable() {
    setState(() {
      _variables = [
        ..._variables,
        const WorkflowFlowVariable(key: '', value: ''),
      ];
    });
  }

  void _removeAt(int index) {
    setState(() {
      _variables = [
        for (var i = 0; i < _variables.length; i++)
          if (i != index) _variables[i],
      ];
    });
  }

  void _updateAt(int index, WorkflowFlowVariable variable) {
    setState(() {
      _variables = [
        for (var i = 0; i < _variables.length; i++)
          if (i == index) variable else _variables[i],
      ];
    });
  }

  Future<void> _save() async {
    final cleaned = <WorkflowFlowVariable>[
      for (final variable in _variables)
        if (variable.key.trim().isNotEmpty)
          variable.copyWith(key: variable.key.trim()),
    ];
    await ref.read(activeWorkflowProvider.notifier).updateWorkflow(
          (current) => current.copyWith(flowVariables: cleaned),
        );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SizedBox(
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kLabelWorkflowVariables,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      kHintWorkflowVariables,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _variables.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No variables yet. Add one to use {{name}} in requests and loops.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                        itemCount: _variables.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final variable = _variables[index];
                          return _VariableRow(
                            variable: variable,
                            onChanged: (updated) => _updateAt(index, updated),
                            onDelete: () => _removeAt(index),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _addVariable,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add variable'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(kLabelCancel),
                    ),
                    kHSpacer8,
                    FilledButton(
                      onPressed: _save,
                      child: const Text(kLabelDone),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariableRow extends StatefulWidget {
  const _VariableRow({
    required this.variable,
    required this.onChanged,
    required this.onDelete,
  });

  final WorkflowFlowVariable variable;
  final ValueChanged<WorkflowFlowVariable> onChanged;
  final VoidCallback onDelete;

  @override
  State<_VariableRow> createState() => _VariableRowState();
}

class _VariableRowState extends State<_VariableRow> {
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.variable.key);
    _valueController = TextEditingController(text: widget.variable.value);
  }

  @override
  void didUpdateWidget(covariant _VariableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variable.key != widget.variable.key &&
        _keyController.text != widget.variable.key) {
      _keyController.text = widget.variable.key;
    }
    if (oldWidget.variable.value != widget.variable.value &&
        _valueController.text != widget.variable.value) {
      _valueController.text = widget.variable.value;
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _keyController,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'items',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                widget.onChanged(widget.variable.copyWith(key: value)),
          ),
        ),
        kHSpacer8,
        Expanded(
          flex: 3,
          child: TextField(
            controller: _valueController,
            decoration: const InputDecoration(
              labelText: 'Value',
              hintText: '["a","b"] or plain text',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
            minLines: 1,
            onChanged: (value) =>
                widget.onChanged(widget.variable.copyWith(value: value)),
          ),
        ),
        kHSpacer4,
        Column(
          children: [
            Switch(
              value: widget.variable.enabled,
              onChanged: (enabled) =>
                  widget.onChanged(widget.variable.copyWith(enabled: enabled)),
            ),
            IconButton(
              tooltip: kTooltipDelete,
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ],
    );
  }
}
