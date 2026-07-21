import 'package:apidash/consts.dart';
import 'package:apidash/workflow/engine/workflow_templates.dart';
import 'package:flutter/material.dart';

Future<WorkflowTemplate?> showWorkflowTemplatePicker(
  BuildContext context,
) {
  return showModalBottomSheet<WorkflowTemplate?>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _WorkflowTemplatePickerSheet(),
  );
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
