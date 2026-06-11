import 'dart:async';

import 'package:apidash/consts.dart';
import 'package:apidash/git/git_models.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/widgets/dialog_git_remote.dart';
import 'package:apidash/widgets/button_group_filled.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class CollaborationPage extends ConsumerStatefulWidget {
  const CollaborationPage({super.key});

  @override
  ConsumerState<CollaborationPage> createState() => _CollaborationPageState();
}

class _CollaborationPageState extends ConsumerState<CollaborationPage> {
  final _messageController = TextEditingController();
  final Set<String> _selectedPaths = {};
  bool _busy = false;
  bool _selectionInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshGitStatus());
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _refreshGitStatus() async {
    await ref.read(autoSaveNotifierProvider.notifier).flushNow();
    ref.invalidate(gitStatusProvider);
  }

  void _syncSelection(List<GitChange> changes) {
    final paths = changes.map((c) => c.path).toSet();
    _selectedPaths.removeWhere((p) => !paths.contains(p));
    for (final change in changes) {
      _selectedPaths.add(change.path);
    }
  }

  Future<void> _run(Future<void> Function() action, String successMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    final sm = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) {
        setState(() {
          _selectionInitialized = false;
          _selectedPaths.clear();
        });
        sm.showSnackBar(getSnackBar(successMessage));
      }
    } catch (e) {
      if (mounted) {
        sm.showSnackBar(getSnackBar(e.toString(), color: kColorRed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsDesktop) {
      return const Center(child: Text('Collaboration is available on desktop only.'));
    }

    ref.listen<int>(navRailIndexStateProvider, (previous, next) {
      if (next == kNavRailCollaborationIndex && previous != next) {
        unawaited(_refreshGitStatus());
      }
    });

    final statusAsync = ref.watch(gitStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: kPh20t40,
          child: Text(
            kLabelCollaboration,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
        ),
        const Padding(padding: kPh20, child: Divider(height: 1)),
        Expanded(
          child: statusAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(e.toString())),
            data: (status) {
              if (!status.gitInstalled) {
                return _EmptyState(
                  message: kMsgGitNotInstalled,
                  actionLabel: 'Download Git',
                  onAction: () => launchUrl(Uri.parse(kGitInstallUrl)),
                );
              }
              if (!status.isRepository) {
                return _EmptyState(
                  message: kMsgGitNotARepository,
                  actionLabel: kLabelInitializeRepository,
                  onAction: _busy
                      ? null
                      : () => _run(
                            () => gitInitRepository(ref),
                            'Repository initialized',
                          ),
                );
              }

              if (!_selectionInitialized && status.changes.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _syncSelection(status.changes);
                      _selectionInitialized = true;
                    });
                  }
                });
              }

              return ListView(
                padding: kPh20,
                children: [
                  Text(
                    _statusSubtitle(status),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (status.remoteUrl != null) ...[
                    kVSpacer5,
                    Text(
                      status.remoteUrl!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (status.errorMessage != null) ...[
                    kVSpacer8,
                    Text(
                      status.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  kVSpacer16,
                  FilledButtonGroup(
                    buttons: [
                      ButtonData(
                        label: kLabelPull,
                        icon: Icons.download_rounded,
                        onPressed: _busy ? null : () => _run(() => gitPull(ref), kMsgGitPullSuccess),
                      ),
                      ButtonData(
                        label: kLabelSync,
                        icon: Icons.cloud_upload_outlined,
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => gitSync(
                                    ref,
                                    message: _messageController.text,
                                    paths: _selectedPaths.toList(),
                                  ),
                                  kMsgGitSyncSuccess,
                                ),
                      ),
                    ],
                  ),
                  if (status.remoteUrl == null) ...[
                    kVSpacer16,
                    _ConnectRemote(
                      busy: _busy,
                      onConnect: () async {
                        final url = await showGitRemoteDialog(context);
                        if (url == null || url.isEmpty || !mounted) return;
                        await _run(
                          () => gitSetRemote(ref, url),
                          'Remote connected',
                        );
                      },
                    ),
                  ],
                  kVSpacer20,
                  if (status.changes.isEmpty)
                    Text(
                      kMsgGitNoChanges,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    )
                  else ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        kLabelSelectAll,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      value: _selectedPaths.length == status.changes.length,
                      tristate: true,
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedPaths.addAll(
                                    status.changes.map((c) => c.path),
                                  );
                                } else {
                                  _selectedPaths.clear();
                                }
                              });
                            },
                    ),
                    for (final change in status.changes)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _selectedPaths.contains(change.path),
                        onChanged: _busy
                            ? null
                            : (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedPaths.add(change.path);
                                  } else {
                                    _selectedPaths.remove(change.path);
                                  }
                                });
                              },
                        title: Text(change.displayName),
                        subtitle: Text(_changeTypeLabel(change.type)),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                  kVSpacer20,
                  ADOutlinedTextField(
                    keyId: 'git-commit-message',
                    controller: _messageController,
                    hintText: kLabelCommitMessage,
                    maxLines: 3,
                  ),
                  kVSpacer20,
                  Text(
                    kLabelRecentCommits,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  kVSpacer8,
                  if (status.recentCommits.isEmpty)
                    Text(
                      'No commits yet',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    )
                  else
                    for (final entry in status.recentCommits)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(entry.message),
                        subtitle: Text('${entry.author} · ${entry.relativeTime}'),
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  String _statusSubtitle(GitStatus status) {
    final branch = status.branch ?? 'unknown';
    final count = status.changes.length;
    final remote = status.remoteUrl != null ? ' · connected' : ' · no remote';
    if (count == 0) return '$branch · no local changes$remote';
    return '$branch · $count change${count == 1 ? '' : 's'}$remote';
  }

  String _changeTypeLabel(GitChangeType type) => switch (type) {
        GitChangeType.added => 'Added',
        GitChangeType.modified => 'Modified',
        GitChangeType.deleted => 'Deleted',
        GitChangeType.untracked => 'Untracked',
        GitChangeType.renamed => 'Renamed',
      };
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.message,
    required this.actionLabel,
    this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sync_alt,
            size: 40,
            color: Theme.of(context).colorScheme.outline,
          ),
          kVSpacer10,
          Text(
            message,
            textAlign: TextAlign.center,
            style: kTextStyleMedium.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          kVSpacer16,
          if (onAction != null)
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

class _ConnectRemote extends StatelessWidget {
  const _ConnectRemote({required this.onConnect, required this.busy});

  final VoidCallback onConnect;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Connect a remote to sync changes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        FilledButton.tonal(
          onPressed: busy ? null : onConnect,
          child: const Text(kLabelConnectRemote),
        ),
      ],
    );
  }
}
