import 'dart:async';

import 'package:apidash/consts.dart';
import 'package:apidash/git/consts.dart';
import 'package:apidash/git/git_error.dart';
import 'package:apidash/git/models/git_change_tree.dart';
import 'package:apidash/git/models/git_models.dart';
import 'package:apidash/git/providers/providers.dart';
import 'package:apidash/git/widgets/dialog_git_remote.dart';
import 'package:apidash/git/widgets/git_changes_tree.dart';
import 'package:apidash/git/widgets/git_diff_panel.dart';
import 'package:apidash/git/widgets/git_overview_panel.dart';
import 'package:apidash/git/widgets/git_recent_commits_section.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/sync/consts.dart';
import 'package:apidash/sync/providers/sync_providers.dart';
import 'package:apidash/sync/ui/sync_host_dialog.dart';
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
  GitChange? _previewChange;
  bool _busy = false;
  bool _selectionInitialized = false;
  int _diffRevision = 0;

  Future<void> _openSyncToPhoneDialog() async {
    if (!mounted) return;
    await showSyncHostDialog(context);
    if (!mounted) return;
    await invalidateSyncUnsyncedCount(ref);
  }

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
    await ref.read(autoSaveNotifierProvider.notifier).flushNow(force: true);
  }

  void _syncSelection(List<GitChange> changes) {
    final paths = changes.map((c) => c.path).toSet();
    _selectedPaths.removeWhere((p) => !paths.contains(p));
    for (final change in changes) {
      _selectedPaths.add(change.path);
    }
    if (_previewChange != null && !paths.contains(_previewChange!.path)) {
      _previewChange = null;
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

  Future<void> _confirmRestoreCommit(GitLogEntry entry) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(kMsgGitRestoreCommitConfirmTitle),
        content: Text(
          '${entry.message}\n\n${entry.author} · ${entry.relativeTime}\n\n'
          '$kMsgGitRestoreCommitConfirmBody',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(kLabelCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(kLabelGitRestoreCommit),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => gitRestoreToCommit(ref, entry.hash),
      kMsgGitRestoreCommitSuccess,
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
          _previewChange = null;
        });
        sm.showSnackBar(getSnackBar(successMessage));
      }
    } catch (e) {
      if (mounted) {
        sm.showSnackBar(
          getSnackBar(formatGitCollaborationError(e), color: kColorRed),
        );
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
    final unsyncedAsync = ref.watch(syncUnsyncedCountProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: kPh20t40,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  kLabelCollaboration,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _openSyncToPhoneDialog,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: unsyncedAsync.maybeWhen(
                  data: (count) => count > 0
                      ? Text('$kLabelSyncToPhone')
                      : const Text(kLabelSyncToPhone),
                  orElse: () => const Text(kLabelSyncToPhone),
                ),
              ),
            ],
          ),
        ),
        const Padding(padding: kPh20, child: Divider(height: 1)),
        Expanded(
          child: statusAsync.when(
            skipLoadingOnReload: true,
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

              final treeRoots = buildGitChangeTree(status.changes);

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (status.errorMessage != null) ...[
                      _InfoBanner(message: status.errorMessage!, isError: true),
                      kVSpacer8,
                    ],
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 300,
                            child: _GitPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _GitSidebarHeader(
                                    status: status,
                                    branches: _branchOptions(status),
                                    busy: _busy,
                                    onBranchSelected: (branch) => _run(
                                      () => gitCheckoutBranch(ref, branch),
                                      kMsgGitCheckoutSuccess,
                                    ),
                                  ),
                                  if (status.recentCommits.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: Text(
                                        kMsgGitSetupSyncBody,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  Expanded(
                                    child: status.changes.isEmpty
                                        ? _EmptyChangesState()
                                        : GitChangesTree(
                                            roots: treeRoots,
                                            selectedPaths: _selectedPaths,
                                            previewPath: _previewChange?.path,
                                            busy: _busy,
                                            onSelectionChanged: (paths) {
                                              setState(() => _selectedPaths
                                                ..clear()
                                                ..addAll(paths));
                                            },
                                            onFilePreview: (change) async {
                                              await ref
                                                  .read(autoSaveNotifierProvider
                                                      .notifier)
                                                  .flushNow(force: true);
                                              if (!mounted) return;
                                              setState(() {
                                                _previewChange = change;
                                                _diffRevision++;
                                              });
                                            },
                                          ),
                                  ),
                                  const Divider(height: 1),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ADOutlinedTextField(
                                          keyId: 'git-commit-message',
                                          controller: _messageController,
                                          hintText: kLabelCommitMessage,
                                          maxLines: 2,
                                        ),
                                        kVSpacer8,
                                        FilledButton.icon(
                                          onPressed: _busy ||
                                                  _selectedPaths.isEmpty ||
                                                  _messageController.text
                                                      .trim()
                                                      .isEmpty
                                              ? null
                                              : () => _run(
                                                    () => gitCommitChanges(
                                                      ref,
                                                      message:
                                                          _messageController
                                                              .text,
                                                      paths: _selectedPaths
                                                          .toList(),
                                                    ),
                                                    kMsgGitCommitSuccess,
                                                  ),
                                          icon: const Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                          ),
                                          label: Text(kLabelCommitChanges),
                                          style: FilledButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                          ),
                                        ),
                                        GitRecentCommitsSection(
                                          commits: status.recentCommits,
                                          busy: _busy,
                                          onRestore: _confirmRestoreCommit,
                                        ),
                                        kVSpacer8,
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          kHSpacer10,
                          Expanded(
                            child: _GitPanel(
                              child: _previewChange == null
                                  ? GitOverviewPanel(
                                      status: status,
                                      busy: _busy,
                                      onFetch: () => _run(
                                        () => gitFetch(ref),
                                        kMsgGitFetchSuccess,
                                      ),
                                      onPull: () => _run(
                                        () => gitPull(ref),
                                        kMsgGitPullSuccess,
                                      ),
                                      onPush: () => _run(
                                        () => gitPush(ref),
                                        kMsgGitPushSuccess,
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: IconButton(
                                            onPressed: _busy
                                                ? null
                                                : () => setState(
                                                      () =>
                                                          _previewChange = null,
                                                    ),
                                            icon: const Icon(
                                              Icons.arrow_back_rounded,
                                              size: 20,
                                            ),
                                            tooltip: kLabelGitBackToOverview,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        ),
                                        Expanded(
                                          child: GitDiffPanel(
                                            change: _previewChange,
                                            refreshToken: _diffRevision,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<String> _branchOptions(GitStatus status) {
    final names = <String>{...status.branches};
    final current = status.branch;
    if (current != null && current.isNotEmpty) {
      names.add(current);
    }
    return names.toList()..sort();
  }
}

class _GitPanel extends StatelessWidget {
  const _GitPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLow.withValues(alpha: 0.55),
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      ),
    );
  }
}

class _GitSidebarHeader extends StatelessWidget {
  const _GitSidebarHeader({
    required this.status,
    required this.branches,
    required this.busy,
    required this.onBranchSelected,
  });

  final GitStatus status;
  final List<String> branches;
  final bool busy;
  final ValueChanged<String> onBranchSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (branches.isNotEmpty)
            _BranchPill(
              branches: branches,
              currentBranch: status.branch,
              busy: busy,
              onBranchSelected: onBranchSelected,
            ),
          if (status.remoteUrl != null) ...[
            kVSpacer5,
            Text(
              status.remoteUrl!,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _BranchPill extends StatelessWidget {
  const _BranchPill({
    required this.branches,
    required this.currentBranch,
    required this.busy,
    required this.onBranchSelected,
  });

  final List<String> branches;
  final String? currentBranch;
  final bool busy;
  final ValueChanged<String> onBranchSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = currentBranch != null && branches.contains(currentBranch)
        ? currentBranch
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: selected,
          icon: Icon(Icons.expand_more_rounded, size: 18, color: scheme.primary),
          items: [
            for (final branch in branches)
              DropdownMenuItem(
                value: branch,
                child: Text(
                  branch,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
          onChanged: busy || selected == null
              ? null
              : (branch) {
                  if (branch == null || branch == selected) return;
                  onBranchSelected(branch);
                },
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: isError ? scheme.error : scheme.onSecondaryContainer,
          ),
          kHSpacer10,
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChangesState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          kMsgGitNoChanges,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
