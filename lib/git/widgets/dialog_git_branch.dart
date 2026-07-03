import 'package:apidash/consts.dart';
import 'package:apidash/git/branch_name.dart';
import 'package:apidash/git/consts.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

Future<String?> showGitBranchDialog(
  BuildContext context, {
  String? suggestedName,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _GitBranchDialog(suggestedName: suggestedName),
  );
}

class _GitBranchDialog extends StatefulWidget {
  const _GitBranchDialog({this.suggestedName});

  final String? suggestedName;

  @override
  State<_GitBranchDialog> createState() => _GitBranchDialogState();
}

class _GitBranchDialogState extends State<_GitBranchDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.suggestedName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    final error = validateGitBranchName(name);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text(kTitleGitNewBranch),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ADOutlinedTextField(
              keyId: 'git-new-branch-name',
              controller: _controller,
              hintText: kHintGitBranchName,
              isDense: true,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
            ),
            if (_errorText != null) ...[
              kVSpacer8,
              Text(
                _errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(kLabelCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(kLabelGitCreateBranch),
        ),
      ],
    );
  }
}
