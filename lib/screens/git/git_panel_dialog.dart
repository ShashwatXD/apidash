import 'package:apidash/models/models.dart';
import 'package:apidash/services/git/git_sync_service.dart';
import 'package:apidash/services/git/github_api_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/collection_providers.dart';

class GitPanelDialog extends ConsumerStatefulWidget {
  const GitPanelDialog({
    super.key,
    required this.collectionId,
    this.startInImportMode = false,
  });

  final String collectionId;
  final bool startInImportMode;

  @override
  ConsumerState<GitPanelDialog> createState() => _GitPanelDialogState();
}

enum _GitTab { push, history, branches }
enum _ConnectStage { form, authorizing }

class _GitPanelDialogState extends ConsumerState<GitPanelDialog>
    with SingleTickerProviderStateMixin {
  final GitHubApiAdapter _api = GitHubApiAdapter();

  late final GitSyncService _syncService;

  late final TabController _tabController;

  _GitTab tab = _GitTab.history;
  bool _busy = false;

  String _selectedBranch = 'main';

  String? _deviceUserCode;
  String? _deviceVerificationUri;
  _ConnectStage _connectStage = _ConnectStage.form;

  String? _historyRemoteHeadSha;
  List<CommitInfo> _historyCommits = const [];
  bool _historyLoading = false;

  List<BranchInfo> _branches = const [];
  bool _branchesLoading = false;

  PushPreview? _pushPreview;
  bool _pushPreviewLoading = false;

  final TextEditingController _repoInputController = TextEditingController();
  final TextEditingController _branchController = TextEditingController(text: 'main');
  late bool _importMode;

  @override
  void initState() {
    super.initState();
    _importMode = widget.startInImportMode;
    _syncService = GitSyncService(ref, _api);
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _tabController.addListener(() {
      final idx = _tabController.index;
      final nextTab = idx == 0 ? _GitTab.push : idx == 1 ? _GitTab.history : _GitTab.branches;
      if (nextTab == tab) return;
      setState(() => tab = nextTab);
      if (idx == 1) _loadHistoryIfNeeded();
      if (idx == 2) _loadBranchesIfNeeded();
      if (idx == 0) _loadPushPreview();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final activeId = ref.read(activeCollectionIdStateProvider);
      if (activeId != widget.collectionId) {
        await ref
            .read(collectionStateNotifierProvider.notifier)
            .switchCollection(widget.collectionId);
      }
      final collections = ref.read(collectionsStateProvider);
      final c = collections[widget.collectionId];
      final branch = c?.gitConnection?.branch ?? 'main';
      if ((c?.gitConnection == null) && _repoInputController.text.trim().isEmpty) {
        _repoInputController.text = _suggestRepoName(c?.name ?? 'new-collection');
      }
      setState(() {
        _selectedBranch = branch;
        _branchController.text = branch;
      });
      _loadHistoryIfNeeded();
      _loadPushPreview();
    });
  }

  String _suggestRepoName(String collectionName) {
    final trimmed = collectionName.trim().toLowerCase();
    if (trimmed.isEmpty) return 'new-collection';
    final slug = trimmed
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'new-collection' : slug;
  }

  @override
  void dispose() {
    _repoInputController.dispose();
    _branchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsStateProvider);
    final active = collections[widget.collectionId];
    final git = active?.gitConnection;

    final repoLabel = git != null ? '${git.owner}/${git.repo}' : 'Not connected';

    if (git == null) {
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 560,
          height: 520,
          child: Column(
            children: [
              _DialogHeader(
                title: active?.name ?? 'Collection',
                subtitle: repoLabel,
                onClose: () => Navigator.of(context).pop(),
              ),
              const Divider(height: 1),
              Expanded(
                child: _buildInitialConnectFlow(),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 920,
        height: 640,
        child: Column(
          children: [
            _DialogHeader(
              title: active?.name ?? 'Collection',
              subtitle: repoLabel,
              onClose: () => Navigator.of(context).pop(),
            ),
            const Divider(height: 1),
            Expanded(
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Push'),
                      Tab(text: 'History'),
                      Tab(text: 'Branches'),
                    ],
                    indicatorColor: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _buildBody(git: git),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialConnectFlow() {
    if (_connectStage == _ConnectStage.authorizing &&
        _deviceUserCode != null &&
        _deviceVerificationUri != null) {
      return _AuthorizeWithGitHubView(
        verificationUri: _deviceVerificationUri!,
        userCode: _deviceUserCode!,
        onOpenVerificationUrl: () async {
          await _api.openVerificationUrl(_deviceVerificationUri!);
        },
      );
    }

    return _ConnectToGitCard(
      importMode: _importMode,
      repoController: _repoInputController,
      branchController: _branchController,
      onConnect: () async {
        await ref
            .read(collectionStateNotifierProvider.notifier)
            .switchCollection(widget.collectionId);
        setState(() {
          _busy = true;
          _connectStage = _ConnectStage.authorizing;
          _deviceUserCode = null;
          _deviceVerificationUri = null;
        });
        try {
          if (_importMode) {
            final malformed = await _syncService.connectAndImportActiveCollection(
              repoInput: _repoInputController.text,
              branch: _branchController.text.trim().isEmpty
                  ? 'main'
                  : _branchController.text.trim(),
              onShowDeviceCode: (userCode, verificationUri) {
                if (!mounted) return;
                setState(() {
                  _deviceUserCode = userCode;
                  _deviceVerificationUri = verificationUri;
                });
              },
              autoOpenBrowser: false,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    malformed.isEmpty
                        ? 'Import complete'
                        : 'Import complete (skipped ${malformed.length} malformed request(s))',
                  ),
                ),
              );
            }
          } else {
            await _syncService.connectAndPushActiveCollection(
              repoInput: _repoInputController.text,
              branch: _branchController.text.trim().isEmpty
                  ? 'main'
                  : _branchController.text.trim(),
              isPrivate: true,
              onShowDeviceCode: (userCode, verificationUri) {
                if (!mounted) return;
                setState(() {
                  _deviceUserCode = userCode;
                  _deviceVerificationUri = verificationUri;
                });
              },
              autoOpenBrowser: false,
            );
          }

          if (!mounted) return;
          setState(() {
            _selectedBranch = _branchController.text.trim().isEmpty
                ? 'main'
                : _branchController.text.trim();
          });
          _tabController.animateTo(1);
          await _loadHistoryIfNeeded();
        } on GitHubApiException catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('GitHub error: ${e.message}')),
          );
          setState(() {
            _connectStage = _ConnectStage.form;
          });
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection failed: $e')),
          );
          setState(() {
            _connectStage = _ConnectStage.form;
          });
        } finally {
          if (mounted) {
            setState(() {
              _busy = false;
            });
          }
        }
      },
      onClearAuth: () async {
        await _api.clearToken();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GitHub auth token removed')),
        );
      },
    );
  }

  Future<void> _loadHistoryIfNeeded() async {
    if (_historyLoading) return;
    final collections = ref.read(collectionsStateProvider);
    final c = collections[widget.collectionId];
    final git = c?.gitConnection;
    if (git == null) return;
    setState(() {
      _historyLoading = true;
    });
    try {
      final payload = await _syncService.loadHistory(branch: _selectedBranch);
      setState(() {
        _historyRemoteHeadSha = payload.headSha;
        _historyCommits = payload.commits;
      });
    } on GitHubApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GitHub error: ${e.message}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _historyLoading = false;
        });
      }
    }
  }

  Future<void> _loadBranchesIfNeeded() async {
    if (_branchesLoading) return;
    final collections = ref.read(collectionsStateProvider);
    final c = collections[widget.collectionId];
    final git = c?.gitConnection;
    if (git == null) return;
    setState(() {
      _branchesLoading = true;
    });
    try {
      final branches = await _syncService.loadBranches();
      setState(() {
        _branches = branches;
      });
    } on GitHubApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GitHub error: ${e.message}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _branchesLoading = false;
        });
      }
    }
  }

  Future<void> _loadPushPreview() async {
    final collections = ref.read(collectionsStateProvider);
    final c = collections[widget.collectionId];
    final git = c?.gitConnection;
    if (git == null) {
      if (mounted) {
        setState(() {
          _pushPreview = null;
          _pushPreviewLoading = false;
        });
      }
      return;
    }

    if (_pushPreviewLoading) return;
    setState(() => _pushPreviewLoading = true);
    try {
      final preview = await _syncService.getPushPreview(branch: _selectedBranch);
      if (!mounted) return;
      setState(() {
        _pushPreview = preview;
      });
    } on GitHubApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GitHub error: ${e.message}')),
      );
    } finally {
      if (mounted) {
        setState(() => _pushPreviewLoading = false);
      }
    }
  }

  Future<String?> _askCommitMessage() async {
    final controller = TextEditingController(
      text: 'Inital Commit',
    );
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Commit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Describe this push',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return message?.trim().isEmpty == true ? null : message?.trim();
  }

  Widget _buildBody({required GitConnectionModel? git}) {
    if (tab == _GitTab.push) {
      return _buildPushTab(git: git);
    }
    if (tab == _GitTab.history) {
      return _buildHistoryTab(git: git);
    }
    return _buildBranchesTab(git: git);
  }

  Widget _buildPushTab({required GitConnectionModel? git}) {
    if (git == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connected to GitHub',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Repo: ${git.owner}/${git.repo}'),
          Text('Branch: $_selectedBranch'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await _api.clearToken();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('GitHub auth token removed')),
                      );
                    },
              child: const Text(''),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await ref
                            .read(collectionStateNotifierProvider.notifier)
                            .switchCollection(widget.collectionId);
                        setState(() => _busy = true);
                        try {
                          final malformed = await _syncService.pullLatestToActiveCollection(
                            branch: _selectedBranch,
                          );
                          await _loadHistoryIfNeeded();
                          await _loadPushPreview();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  malformed.isEmpty
                                      ? 'Pull complete'
                                      : 'Pull complete (skipped ${malformed.length} malformed request(s))',
                                ),
                              ),
                            );
                          }
                        } on GitHubApiException catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('GitHub error: ${e.message}')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('Pull latest'),
              ),
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () async {
                        final commitMessage = await _askCommitMessage();
                        if (commitMessage == null) return;
                        await ref
                            .read(collectionStateNotifierProvider.notifier)
                            .switchCollection(widget.collectionId);
                        setState(() => _busy = true);
                        try {
                          await _syncService.pushActiveCollection(
                            branch: _selectedBranch,
                            commitMessage: commitMessage,
                          );
                          await _loadHistoryIfNeeded();
                          await _loadPushPreview();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Push complete')),
                            );
                          }
                        } on GitSyncConflictException catch (e) {
                          await showDialog<void>(
                            context: context,
                            builder: (context) => _PushConflictDialog(
                              remoteSha: e.remoteSha,
                              expectedSha: e.expectedSha,
                              onPullLatest: () async {
                                Navigator.of(context).pop();
                                setState(() => _busy = true);
                                try {
                                  await _syncService.pullLatestToActiveCollection(branch: _selectedBranch);
                                  await _loadHistoryIfNeeded();
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                              onViewCommits: () async {
                                Navigator.of(context).pop();
                                _tabController.animateTo(1);
                                await _loadHistoryIfNeeded();
                              },
                            ),
                          );
                        } on GitHubApiException catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('GitHub error: ${e.message}')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Push failed: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('Push changes'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PushPreviewCard(
            loading: _pushPreviewLoading,
            preview: _pushPreview,
            onRefresh: _busy ? null : _loadPushPreview,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab({required GitConnectionModel? git}) {
    if (git == null) {
      return const Center(child: Text('Connect the collection first.'));
    }
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_historyCommits.isEmpty) {
      return const Center(child: Text('No commit history loaded.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _historyCommits.length,
      itemBuilder: (context, index) {
        final c = _historyCommits[index];
        final isCurrent = _historyRemoteHeadSha != null && _historyRemoteHeadSha == c.sha;
        return _CommitCard(
          message: c.message,
          shortSha: c.sha.substring(0, c.sha.length > 7 ? 7 : c.sha.length),
          author: c.authorName ?? 'unknown',
          date: c.date,
          isCurrent: isCurrent,
          onRollback: () async {
            await ref
                .read(collectionStateNotifierProvider.notifier)
                .switchCollection(widget.collectionId);
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Rollback collection'),
                content: Text('Rollback to ${c.sha.substring(0, 7)}? This replaces the entire collection.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Rollback'),
                  ),
                ],
              ),
            );
            if (ok != true) return;

            setState(() => _busy = true);
            try {
              final malformed = await _syncService.rollbackActiveCollectionToCommit(
                commitSha: c.sha,
                branch: _selectedBranch,
              );
              await _loadHistoryIfNeeded();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      malformed.isEmpty
                          ? 'Rollback complete'
                          : 'Rollback complete (skipped ${malformed.length} malformed request(s))',
                    ),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
          onOpenGithub: () {
            final url = 'https://github.com/${git.owner}/${git.repo}/commit/${c.sha}';
                launchUrl(Uri.parse(url));
          },
        );
      },
    );
  }

  Widget _buildBranchesTab({required GitConnectionModel? git}) {
    if (git == null) {
      return const Center(child: Text('Connect the collection first.'));
    }
    if (_branchesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Branches in ${git.owner}/${git.repo}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _branches.length,
              itemBuilder: (context, index) {
                final b = _branches[index];
                final isSelected = _selectedBranch == b.name;
                return ListTile(
                  dense: true,
                  title: Text(b.name),
                  subtitle: Text('HEAD: ${b.sha.substring(0, 7)}'),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_outline)
                      : TextButton(
                          onPressed: () {
                            setState(() => _selectedBranch = b.name);
                            _tabController.animateTo(1);
                            _loadHistoryIfNeeded();
                          },
                          child: const Text('Switch'),
                        ),
                  onLongPress: () async {
                    if (b.protected) return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete branch'),
                        content: Text('Delete ${b.name}?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;

                    setState(() => _busy = true);
                    try {
                      await _api.deleteBranch(owner: git.owner, repo: git.repo, branchName: b.name);
                      await _loadBranchesIfNeeded();
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _branchController,
                  decoration: const InputDecoration(
                    labelText: 'Create new branch name',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final newName = _branchController.text.trim();
                        if (newName.isEmpty) return;
                        setState(() => _busy = true);
                        try {
                          final headSha = await _api.getBranchHeadSha(owner: git.owner, repo: git.repo, branch: _selectedBranch);
                          await _api.createBranch(owner: git.owner, repo: git.repo, branchName: newName, fromSha: headSha);
                          await _loadBranchesIfNeeded();
                          setState(() => _selectedBranch = newName);
                          await _loadHistoryIfNeeded();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ConnectToGitCard extends StatelessWidget {
  const _ConnectToGitCard({
    required this.importMode,
    required this.repoController,
    required this.branchController,
    required this.onConnect,
    required this.onClearAuth,
  });

  final bool importMode;
  final TextEditingController repoController;
  final TextEditingController branchController;
  final Future<void> Function() onConnect;
  final Future<void> Function() onClearAuth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connect to GitHub', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          TextField(
            controller: repoController,
            decoration: const InputDecoration(
              labelText: 'Enter Repo URL',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: branchController,
            decoration: const InputDecoration(
              labelText: 'Branch',
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onConnect,
            child: Text(
              importMode
                  ? 'Import Collection from GitHub'
                  : 'Create Repository',
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onClearAuth,
            child: const Text(''),
          ),
        ],
      ),
    );
  }
}

class _AuthorizeWithGitHubView extends StatelessWidget {
  const _AuthorizeWithGitHubView({
    required this.verificationUri,
    required this.userCode,
    required this.onOpenVerificationUrl,
  });

  final String verificationUri;
  final String userCode;
  final Future<void> Function() onOpenVerificationUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Authorize with GitHub',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open the verification URL, then enter the code below.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: onOpenVerificationUrl,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open verification page'),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.4),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            userCode,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy code',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: userCode));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Code copied')),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Waiting for authorization...',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PushConflictDialog extends StatelessWidget {
  const _PushConflictDialog({
    required this.remoteSha,
    required this.expectedSha,
    required this.onPullLatest,
    required this.onViewCommits,
  });

  final String remoteSha;
  final String? expectedSha;
  final VoidCallback onPullLatest;
  final VoidCallback onViewCommits;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Push failed'),
      content: Text(
        'Remote has new commits. Pull latest and review changes before pushing again.\n\nRemote HEAD: ${remoteSha.substring(0, 7)}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: onPullLatest,
          child: const Text('Pull latest'),
        ),
        OutlinedButton(
          onPressed: onViewCommits,
          child: const Text('View commits'),
        ),
      ],
    );
  }
}

class _CommitCard extends StatelessWidget {
  const _CommitCard({
    required this.message,
    required this.shortSha,
    required this.author,
    required this.date,
    required this.isCurrent,
    required this.onRollback,
    required this.onOpenGithub,
  });

  final String message;
  final String shortSha;
  final String author;
  final DateTime? date;
  final bool isCurrent;
  final Future<void> Function() onRollback;
  final VoidCallback onOpenGithub;

  @override
  Widget build(BuildContext context) {
    final dLabel = date == null
        ? ''
        : ' · ${date!.toLocal().toString().substring(0, 16).replaceFirst('T', ' ')}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$shortSha · $author$dLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            if (isCurrent)
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('current', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            TextButton(
              onPressed: () async => await onRollback(),
              child: const Text('Rollback'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onOpenGithub,
              child: const Text('GitHub'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PushPreviewCard extends StatelessWidget {
  const _PushPreviewCard({
    required this.loading,
    required this.preview,
    required this.onRefresh,
  });

  final bool loading;
  final PushPreview? preview;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Changes to push',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh status',
                  onPressed: onRefresh == null ? null : () async => await onRefresh!(),
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else if (p == null)
              const Text('No status yet.')
            else if (p.changes.isEmpty)
              const Text('Working tree clean. Nothing to push.')
            else ...[
              Text(
                'Added: ${p.addedCount}  ·  Modified: ${p.modifiedCount}  ·  Deleted: ${p.deletedCount}',
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: p.changes.length,
                  itemBuilder: (context, index) {
                    final c = p.changes[index];
                    final (label, color) = switch (c.type) {
                      PushChangeType.added => ('A', const Color(0xFF1D9E75)),
                      PushChangeType.modified => ('M', const Color(0xFF3B82F6)),
                      PushChangeType.deleted => ('D', const Color(0xFFDC2626)),
                    };
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            child: Text(
                              label,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

