import 'dart:async';

import 'package:apidash/consts.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/providers/providers.dart';
import 'package:apidash/git/widgets/dialog_git_remote.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/widgets/button_group_filled.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collaboration_setup_guide.dart';

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

  Future<void> _connectRemote() async {
    final url = await showGitRemoteDialog(context);
    if (url == null || url.isEmpty || !mounted) return;
    await _run(
      () => gitSetRemote(ref, url),
      'Remote connected',
    );
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

    ref.watch(gitWorkspaceWatchProvider);
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
              if (!status.gitInstalled ||
                  !status.isRepository ||
                  status.remoteUrl == null) {
                return CollaborationSetupGuide(
                  status: status,
                  busy: _busy,
                  onInitialize: _busy
                      ? null
                      : () => _run(
                            () => gitInitRepository(ref),
                            'Repository initialized',
                          ),
                  onConnectRemote: _busy ? null : _connectRemote,
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
                  if (status.recentCommits.isEmpty)
                    Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.35),
                      child: Padding(
                        padding: kP12,
                        child: Text(
                          kMsgGitSetupSyncBody,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  if (status.recentCommits.isEmpty) kVSpacer16,
                  if (status.branches.length > 1) ...[
                    Row(
                      children: [
                        Text(
                          kLabelBranch,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        kHSpacer10,
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: status.branch != null &&
                                    status.branches.contains(status.branch)
                                ? status.branch
                                : null,
                            items: [
                              for (final branch in status.branches)
                                DropdownMenuItem(
                                  value: branch,
                                  child: Text(branch),
                                ),
                            ],
                            onChanged: _busy || status.branch == null
                                ? null
                                : (branch) {
                                    if (branch == null ||
                                        branch == status.branch) {
                                      return;
                                    }
                                    _run(
                                      () => gitCheckoutBranch(ref, branch),
                                      kMsgGitCheckoutSuccess,
                                    );
                                  },
                          ),
                        ),
                      ],
                    ),
                    kVSpacer10,
                  ],
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
                        onPressed: _busy
                            ? null
                            : () => _run(() => gitPull(ref), kMsgGitPullSuccess),
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
                        title: Text(change.path),
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
                        subtitle: Text(entry.author),
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
