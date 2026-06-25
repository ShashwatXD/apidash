import 'package:apidash/consts.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/services/services.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../collaboration/sync_scan_page.dart';
import 'mobile_workspace_service.dart';

class MobileWorkspaceSelector extends ConsumerWidget {
  const MobileWorkspaceSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final label = savedWorkspaceNameForPath(
          settings.savedWorkspaces,
          settings.workspaceFolderPath,
        ) ??
        kLabelSelectWorkspace;

    return InkWell(
      borderRadius: kBorderRadius8,
      onTap: () => showMobileWorkspaceSheet(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.workspaces_outlined, size: 16, color: scheme.primary),
            kHSpacer8,
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.unfold_more_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showMobileWorkspaceSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => const _MobileWorkspaceSheet(),
  );
}

class _MobileWorkspaceSheet extends ConsumerWidget {
  const _MobileWorkspaceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = ref.watch(settingsProvider);
    final workspaces = settings.savedWorkspaces;
    final activePath = p.normalize(settings.workspaceFolderPath ?? '');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                kLabelWorkspaces,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: workspaces.length,
                itemBuilder: (context, index) {
                  final ws = workspaces[index];
                  final isActive = p.normalize(ws.path) == activePath;
                  final canDelete = workspaces.length > 1 || isActive;
                  return ListTile(
                    leading: Icon(
                      isActive
                          ? Icons.check_circle_rounded
                          : Icons.folder_outlined,
                      color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      ws.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () async {
                      final navigator = Navigator.of(context);
                      if (!isActive) {
                        await activateWorkspace(
                          ref,
                          ws.path,
                          createIfMissing: false,
                        );
                      }
                      navigator.pop();
                    },
                    trailing: PopupMenuButton<_WsRowAction>(
                      tooltip: kLabelMoreOptions,
                      onSelected: (action) =>
                          _onRowAction(context, ref, action, ws, canDelete),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _WsRowAction.rename,
                          child: Text(kLabelRenameWorkspace),
                        ),
                        PopupMenuItem(
                          value: _WsRowAction.delete,
                          enabled: canDelete,
                          child: const Text(kLabelDeleteWorkspace),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 8),
            ListTile(
              leading: Icon(Icons.add_rounded, color: scheme.primary),
              title: const Text(kLabelNewWorkspace),
              onTap: () => _onCreateWorkspace(context, ref),
            ),
            ListTile(
              leading: Icon(Icons.qr_code_scanner_rounded, color: scheme.primary),
              title: const Text(kLabelAddWorkspaceViaSync),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (context) => const SyncScanPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onRowAction(
    BuildContext context,
    WidgetRef ref,
    _WsRowAction action,
    SavedWorkspaceEntry ws,
    bool canDelete,
  ) {
    switch (action) {
      case _WsRowAction.rename:
        _onRename(context, ref, ws);
      case _WsRowAction.delete:
        if (!canDelete) return;
        _confirmDelete(context, ref, ws);
    }
  }

  Future<void> _onRename(
    BuildContext context,
    WidgetRef ref,
    SavedWorkspaceEntry ws,
  ) async {
    final name = await _promptWorkspaceName(
      context,
      title: kLabelRenameWorkspace,
      initial: ws.name,
      isTaken: (n) => _isNameTaken(ref, n, excludePath: ws.path),
    );
    if (name == null) return;
    await renameMobileWorkspace(ref, path: ws.path, name: name);
  }

  bool _isNameTaken(WidgetRef ref, String name, {String? excludePath}) {
    final target = name.trim().toLowerCase();
    final exclude = excludePath == null ? null : p.normalize(excludePath);
    return ref.read(settingsProvider).savedWorkspaces.any(
          (e) =>
              e.name.trim().toLowerCase() == target &&
              (exclude == null || p.normalize(e.path) != exclude),
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SavedWorkspaceEntry ws,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(kLabelDeleteWorkspace),
        content: Text('Delete "${ws.name}" and all its data from this phone?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(kLabelCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(kLabelDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await deleteMobileWorkspace(ref, ws.path);
    if (ok) {
      navigator.pop();
    } else {
      messenger.showSnackBar(getSnackBar(kMsgWorkspaceDeleteFailed));
    }
  }

  Future<void> _onCreateWorkspace(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = await _promptWorkspaceName(
      context,
      title: kLabelNewWorkspaceTitle,
      initial: kDefaultMobileWorkspaceName,
      isTaken: (n) => _isNameTaken(ref, n),
    );
    if (name == null) return;
    final id = await createMobileWorkspace(ref, name: name);
    if (id == null) {
      messenger.showSnackBar(getSnackBar(kMsgWorkspaceCreateFailed));
      return;
    }
    navigator.pop();
  }

  Future<String?> _promptWorkspaceName(
    BuildContext context, {
    required String title,
    String? initial,
    required bool Function(String name) isTaken,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _WorkspaceNameDialog(
        title: title,
        initial: initial,
        isTaken: isTaken,
      ),
    );
  }
}

enum _WsRowAction { rename, delete }

class _WorkspaceNameDialog extends StatefulWidget {
  const _WorkspaceNameDialog({
    required this.title,
    required this.isTaken,
    this.initial,
  });

  final String title;
  final bool Function(String name) isTaken;
  final String? initial;

  @override
  State<_WorkspaceNameDialog> createState() => _WorkspaceNameDialogState();
}

class _WorkspaceNameDialogState extends State<_WorkspaceNameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = kMsgWorkspaceNameEmpty);
      return;
    }
    if (widget.isTaken(name)) {
      setState(() => _error = kMsgWorkspaceNameExists);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.workspaces_outlined),
      iconColor: Theme.of(context).colorScheme.primary,
      title: Text(widget.title),
      titleTextStyle: Theme.of(context).textTheme.titleLarge,
      content: SizedBox(
        width: 300,
        child: TextField(
          autofocus: true,
          controller: _controller,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: kLabelNewWorkspaceTitle,
            errorText: _error,
            border: const OutlineInputBorder(borderRadius: kBorderRadius12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(kLabelCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(kLabelOk),
        ),
      ],
    );
  }
}
