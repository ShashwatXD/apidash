import 'package:apidash/consts.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowVariableBrowser extends ConsumerWidget {
  const WorkflowVariableBrowser({
    super.key,
    required this.nodeId,
  });

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflow = ref.watch(activeWorkflowProvider);
    if (workflow == null) {
      return const SizedBox.shrink();
    }

    final flowVariables = [
      for (final variable in workflow.flowVariables)
        if (variable.enabled && variable.key.isNotEmpty)
          _VariableEntry(
            label: variable.key,
            reference: '{{${variable.key}}}',
            subtitle: 'Flow variable',
          ),
    ];

    final upstream = _upstreamRequestNodes(workflow, nodeId);
    final chained = <_VariableEntry>[
      for (final upstreamNode in upstream)
        for (final extraction in upstreamNode.extractions)
          if (extraction.varName.isNotEmpty)
            _VariableEntry(
              label: extraction.varName,
              reference: '{{${extraction.varName}}}',
              subtitle: '${upstreamNode.label} · ${extraction.jsonPath}',
            ),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          kLabelWorkflowVariables,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          kHintWorkflowVariableInsert,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(height: 12),
        if (flowVariables.isNotEmpty) ...[
          _SectionHeader(title: 'Flow'),
          ...flowVariables.map((entry) => _VariableTile(entry: entry)),
          const SizedBox(height: 12),
        ],
        if (chained.isNotEmpty) ...[
          _SectionHeader(title: 'From upstream steps'),
          ...chained.map((entry) => _VariableTile(entry: entry)),
        ],
        if (flowVariables.isEmpty && chained.isEmpty)
          Padding(
            padding: kP12,
            child: Text(
              'Add variables with the Variables button in the toolbar, or connect upstream steps with extractions.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  List<WorkflowGraphNode> _upstreamRequestNodes(
    WorkflowDocument workflow,
    String targetNodeId,
  ) {
    final predecessors = <String>{};
    final queue = <String>[targetNodeId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final edge in workflow.graph.edges) {
        if (edge.target != current) {
          continue;
        }
        if (predecessors.add(edge.source)) {
          queue.add(edge.source);
        }
      }
    }

    return [
      for (final node in workflow.graph.nodes)
        if (predecessors.contains(node.id) &&
            node.type == WorkflowNodeType.request)
          node,
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _VariableEntry {
  const _VariableEntry({
    required this.label,
    required this.reference,
    required this.subtitle,
  });

  final String label;
  final String reference;
  final String subtitle;
}

class _VariableTile extends StatelessWidget {
  const _VariableTile({required this.entry});

  final _VariableEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        entry.reference,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
      ),
      subtitle: Text(entry.subtitle),
      trailing: IconButton(
        tooltip: 'Copy',
        icon: const Icon(Icons.copy_rounded, size: 18),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: entry.reference));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied ${entry.reference}'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
      ),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: entry.reference));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied ${entry.reference}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
    );
  }
}
