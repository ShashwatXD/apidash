import 'package:apidash/consts.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

Future<String?> showGitRemoteDialog(BuildContext context, {String? initialUrl}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _GitRemoteDialog(initialUrl: initialUrl),
  );
}

class _GitRemoteDialog extends StatefulWidget {
  const _GitRemoteDialog({this.initialUrl});

  final String? initialUrl;

  @override
  State<_GitRemoteDialog> createState() => _GitRemoteDialogState();
}

class _GitRemoteDialogState extends State<_GitRemoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Remote repository URL'),
      content: SizedBox(
        width: 400,
        child: ADOutlinedTextField(
          keyId: 'git-remote-url',
          controller: _controller,
          hintText: 'https://github.com/user/repo.git',
          isDense: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(kLabelCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text(kLabelConnectRemote),
        ),
      ],
    );
  }
}
