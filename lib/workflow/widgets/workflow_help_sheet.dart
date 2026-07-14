import 'package:apidash/consts.dart';
import 'package:apidash/workflow/engine/workflow_templates.dart';
import 'package:flutter/material.dart';

Future<void> showWorkflowHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _WorkflowHelpSheet(),
  );
}

Future<WorkflowTemplate?> showWorkflowTemplatePicker(
  BuildContext context,
) {
  return showModalBottomSheet<WorkflowTemplate?>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _WorkflowTemplatePickerSheet(),
  );
}

class _WorkflowHelpSheet extends StatelessWidget {
  const _WorkflowHelpSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: const [
          _HelpSection(
            title: 'What workflows do',
            body:
                'Run API scenarios: chain requests, pass data between steps, branch on results, and repeat actions.',
          ),
          _HelpSection(
            title: 'Request',
            body:
                'Calls an API. Double-click to edit the URL, headers, and body. Add extractions to save values from the response.',
          ),
          _HelpSection(
            title: 'Condition',
            body:
                'Branches after a request. Wire True and False to different next steps. Use presets like HTTP success or a variable check.',
          ),
          _HelpSection(
            title: 'For each / Repeat',
            body:
                'For each runs once per list item (set items under Variables). Repeat runs the same step N times — no list needed.',
          ),
          _HelpSection(
            title: 'Variables',
            body:
                'Workflow variables are inputs you set before running. Use {{name}} in requests. Extractions create variables from responses.',
          ),
          _HelpSection(
            title: 'Ports',
            body:
                'Drag from a port to connect steps. Loop uses In, Each (body), and Done (after all iterations).',
          ),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowTemplatePickerSheet extends StatelessWidget {
  const _WorkflowTemplatePickerSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              kLabelWorkflowTemplates,
              style: theme.textTheme.titleLarge,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text(kLabelWorkflowNewBlank),
            subtitle: const Text('Start with a single empty request.'),
            onTap: () => Navigator.of(context).pop(),
          ),
          const Divider(height: 1),
          for (final info in WorkflowTemplates.templates)
            ListTile(
              leading: Icon(info.icon),
              title: Text(info.title),
              subtitle: Text(info.subtitle),
              onTap: () => Navigator.of(context).pop(info.template),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
