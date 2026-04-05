import 'package:apidash_core/apidash_core.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/providers/collection_providers.dart';
import 'package:apidash/providers/environment_providers.dart';
import 'package:apidash/providers/settings_providers.dart';
import 'package:apidash/services/git_collection_serializer.dart';
import 'package:apidash/services/file_system_handler.dart';
import 'package:apidash/services/git/github_api_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GitSyncNotConnectedException implements Exception {
  GitSyncNotConnectedException(this.message);
  final String message;
}

class GitSyncConflictException implements Exception {
  GitSyncConflictException({
    required this.expectedSha,
    required this.remoteSha,
  });

  final String? expectedSha;
  final String remoteSha;
}

class GitSyncService {
  GitSyncService(this.ref, this.api);

  final WidgetRef ref;
  final GitHubApiAdapter api;

  final GitCollectionSerializer _serializer = const GitCollectionSerializer();
  static const String _repoReadmePath = 'README.md';
  static const String _repoWorkflowPath = '.github/workflows/apidash-git-sync.yml';

  Future<PushPreview> getPushPreview({
    required String branch,
  }) async {
    await ref.read(collectionStateNotifierProvider.notifier).saveData();
    final git = _getActiveGitConnection();
    final localFiles = await _buildFilesFromLocalSnapshot();

    Map<String, String> remoteFiles = const <String, String>{};
    try {
      final pull = await api.pullCollectionAtBranchHead(
        owner: git.owner,
        repo: git.repo,
        branch: branch,
      );
      remoteFiles = pull.files;
    } on GitHubApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 409) rethrow;
      remoteFiles = const <String, String>{};
    }

    final changes = <PushFileChange>[];
    final allPaths = <String>{...localFiles.keys, ...remoteFiles.keys}.toList()
      ..sort();
    for (final path in allPaths) {
      final local = localFiles[path];
      final remote = remoteFiles[path];
      if (remote == null && local != null) {
        changes.add(PushFileChange(path: path, type: PushChangeType.added));
        continue;
      }
      if (remote != null && local == null) {
        changes.add(PushFileChange(path: path, type: PushChangeType.deleted));
        continue;
      }
      if (remote != null && local != null && remote != local) {
        changes.add(PushFileChange(path: path, type: PushChangeType.modified));
      }
    }

    return PushPreview(changes: changes);
  }

  CollectionModel _getActiveCollection() {
    final activeId = ref.read(activeCollectionIdStateProvider);
    final collections = ref.read(collectionsStateProvider);
    if (activeId == null || !collections.containsKey(activeId)) {
      throw GitSyncNotConnectedException('No active collection found');
    }
    return collections[activeId]!;
  }

  GitConnectionModel _getActiveGitConnection() {
    final c = _getActiveCollection();
    final git = c.gitConnection;
    if (git == null || git.owner.isEmpty || git.repo.isEmpty) {
      throw GitSyncNotConnectedException('Collection is not connected to GitHub');
    }
    return git;
  }

  Future<Map<String, String>> _buildFilesFromLocalSnapshot() async {
    final activeCollection = _getActiveCollection();
    final collectionId = activeCollection.id;

    final requestOrder = (await fileSystemHandler.getCollectionRequestIds(collectionId) as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];

    final requestsById = <String, RequestModel>{};
    for (final requestId in requestOrder) {
      final raw = await fileSystemHandler.getCollectionRequestModel(collectionId, requestId);
      if (raw is! Map) continue;
      try {
        final json = raw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        requestsById[requestId] = RequestModel.fromJson(json);
      } catch (_) {}
    }

    final environmentOrder = (fileSystemHandler.getEnvironmentIds() as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];
    final environmentsById = <String, EnvironmentModel>{};
    for (final envId in environmentOrder) {
      final raw = fileSystemHandler.getEnvironment(envId);
      if (raw is! Map) continue;
      try {
        final json = raw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        environmentsById[envId] = EnvironmentModel.fromJson(json);
      } catch (_) {}
    }

    final collectionMeta = await fileSystemHandler.getCollectionMeta(collectionId);
    String collectionName = activeCollection.name;
    String collectionDescription = activeCollection.description;
    String? activeEnvironmentId = ref.read(activeEnvironmentIdStateProvider);
    if (collectionMeta is Map) {
      final meta = collectionMeta.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      collectionName = (meta['name'] as String?) ?? collectionName;
      collectionDescription =
          (meta['description'] as String?) ?? collectionDescription;
      activeEnvironmentId =
          (meta['activeEnvironmentId'] as String?) ?? activeEnvironmentId;
    }

    final collectionModel = CollectionModel(
      id: collectionId,
      name: collectionName,
      description: collectionDescription,
      requestIds: requestOrder,
      activeEnvironmentId: activeEnvironmentId,
      gitConnection: null,
    );

    final files = _serializer.toGitFiles(
      collection: collectionModel,
      requestsById: requestsById,
      requestOrder: requestOrder,
      environmentsById: environmentsById,
      environmentOrder: environmentOrder,
      activeEnvironmentId: activeEnvironmentId,
    );
    return files.files;
  }

  Future<void> connectAndPushActiveCollection({
    required String repoInput,
    required String branch,
    required bool isPrivate,
    required void Function(String userCode, String verificationUri) onShowDeviceCode,
    bool autoOpenBrowser = true,
    String? commitMessage,
  }) async {
    final activeCollection = _getActiveCollection();

    final connected = await api.isAuthenticated();
    if (!connected) {
      await api.authenticateWithDeviceFlow(
        onShowCode: onShowDeviceCode,
        autoOpenBrowser: autoOpenBrowser,
      );
    }
    await api.ensureRequiredScopes();

    final existingGit = activeCollection.gitConnection;
    final repo = existingGit != null
        ? <String, String>{
            'owner': existingGit.owner,
            'repo': existingGit.repo,
          }
        : await _resolveOrCreateRepo(repoInput: repoInput, private: isPrivate);

    final gitConnection = GitConnectionModel(
      owner: repo['owner']!,
      repo: repo['repo']!,
      branch: branch,
      lastSyncedCommitSha: null,
      lastPushedAt: null,
      lastPulledAt: null,
    );

    await ref
        .read(collectionStateNotifierProvider.notifier)
        .setActiveCollectionGitConnection(gitConnection);

    await pushActiveCollection(
      branch: branch,
      commitMessage: commitMessage ?? 'Initial Commit',
    );
  }

  Future<List<MalformedRequestFile>> connectAndImportActiveCollection({
    required String repoInput,
    required String branch,
    required void Function(String userCode, String verificationUri) onShowDeviceCode,
    bool autoOpenBrowser = true,
  }) async {
    final activeCollection = _getActiveCollection();
    final connected = await api.isAuthenticated();
    if (!connected) {
      await api.authenticateWithDeviceFlow(
        onShowCode: onShowDeviceCode,
        autoOpenBrowser: autoOpenBrowser,
      );
    }
    await api.ensureRequiredScopes();

    final existingGit = activeCollection.gitConnection;
    final repo = existingGit != null
        ? <String, String>{
            'owner': existingGit.owner,
            'repo': existingGit.repo,
          }
        : await _resolveExistingRepo(repoInput: repoInput);

    final gitConnection = GitConnectionModel(
      owner: repo['owner']!,
      repo: repo['repo']!,
      branch: branch,
      lastSyncedCommitSha: null,
      lastPushedAt: null,
      lastPulledAt: null,
    );

    await ref
        .read(collectionStateNotifierProvider.notifier)
        .setActiveCollectionGitConnection(gitConnection);

    return pullLatestToActiveCollection(branch: branch);
  }

  Future<Map<String, String>> _resolveOrCreateRepo({
    required String repoInput,
    required bool private,
  }) async {
    final trimmed = repoInput.trim();
    final parsed = _parseGitHubRepoInput(trimmed);
    final owner = parsed.$1;
    final repo = parsed.$2;

    if (repo != null && owner != null) {
      final ownerName = owner;
      final repoName = repo;
      await api.getRepository(ownerName, repoName);
      return {'owner': ownerName, 'repo': repoName};
    }

    final repoName = trimmed;
    if (repoName.isEmpty) {
      throw ArgumentError('repoInput is empty');
    }
    final userLogin = await api.getCurrentUserLogin();
    try {
      await api.getRepository(userLogin, repoName);
    } on GitHubApiException catch (e) {
      if (e.statusCode == 404) {
        await api.createRepository(name: repoName, private: private);
      } else {
        rethrow;
      }
    }
    return {'owner': userLogin, 'repo': repoName};
  }

  Future<Map<String, String>> _resolveExistingRepo({
    required String repoInput,
  }) async {
    final trimmed = repoInput.trim();
    final parsed = _parseGitHubRepoInput(trimmed);
    final owner = parsed.$1;
    final repo = parsed.$2;

    if (repo == null || owner == null) {
      throw ArgumentError('Provide repository as owner/repo');
    }

    final ownerName = owner;
    final repoName = repo;
    await api.getRepository(ownerName, repoName);
    return {'owner': ownerName, 'repo': repoName};
  }

  (String?, String?) _parseGitHubRepoInput(String input) {
    if (input.isEmpty) return (null, null);

    final uri = Uri.tryParse(input);
    if (uri != null && uri.host.toLowerCase().contains('github.com')) {
      final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        final owner = parts[0];
        final repo = parts[1].replaceAll(RegExp(r'\.git$'), '');
        return (owner, repo);
      }
    }

    if (input.contains('/')) {
      final parts = input.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        final owner = parts[0];
        final repo = parts[1].replaceAll(RegExp(r'\.git$'), '');
        return (owner, repo);
      }
    }

    return (null, null);
  }

  Future<void> pushActiveCollection({
    required String branch,
    String? commitMessage,
  }) async {
    await ref.read(collectionStateNotifierProvider.notifier).saveData();
    final git = _getActiveGitConnection();

    String? remoteHead;
    try {
      remoteHead = await api.getBranchHeadSha(
        owner: git.owner,
        repo: git.repo,
        branch: branch,
      );
    } on GitHubApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 409) rethrow;
      remoteHead = null;
    }

    if (git.lastSyncedCommitSha != null &&
        remoteHead != null &&
        git.lastSyncedCommitSha != remoteHead) {
      throw GitSyncConflictException(
        expectedSha: git.lastSyncedCommitSha,
        remoteSha: remoteHead,
      );
    }

    final preview = await getPushPreview(branch: branch);
    if (preview.changes.isEmpty && remoteHead != null) {
      final updatedGit = git.copyWith(
        branch: branch,
        lastSyncedCommitSha: remoteHead,
      );
      await ref
          .read(collectionStateNotifierProvider.notifier)
          .setActiveCollectionGitConnection(updatedGit);
      return;
    }

    var files = await _buildFilesFromLocalSnapshot();
    final isInitialRepoCommit = remoteHead == null;
    if (isInitialRepoCommit) {
      files = _withBootstrapRepoFiles(files);
    }

    final newCommitSha = await api.pushFiles(
      owner: git.owner,
      repo: git.repo,
      branch: branch,
      files: files,
      commitMessage: commitMessage ?? 'Initial Commit',
    );

    final updatedGit = git.copyWith(
      lastSyncedCommitSha: newCommitSha,
      lastPushedAt: DateTime.now(),
    );
    await ref
        .read(collectionStateNotifierProvider.notifier)
        .setActiveCollectionGitConnection(updatedGit);
  }

  Map<String, String> _withBootstrapRepoFiles(Map<String, String> files) {
    final out = Map<String, String>.from(files);
    out[_repoReadmePath] = _initialReadmeContent;
    out[_repoWorkflowPath] = _initialWorkflowContent;
    return out;
  }

  static const String _initialReadmeContent = '''
# API Dash Collection Repository

This repository is managed by API Dash for one collection sync.

## Files

- `collection.json` - collection metadata and request order
- `environments.json` - environments and variables
- `requests/*.json` - individual requests

You can now manage this repository and workflow as needed.
''';

  static const String _initialWorkflowContent = r'''
name: API Dash Git Sync

on:
  push:
    branches:
      - '**'
  pull_request:
    types: [opened, synchronize, reopened, closed]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - name: Print event summary
        run: |
          echo "event: ${{ github.event_name }}"
          echo "repo: ${{ github.repository }}"
          echo "actor: ${{ github.actor }}"
          echo "ref: ${{ github.ref }}"
          echo "sha: ${{ github.sha }}"
      - name: PR merge info
        if: github.event_name == 'pull_request'
        run: |
          echo "pr: #${{ github.event.pull_request.number }}"
          echo "merged: ${{ github.event.pull_request.merged }}"
          echo "base: ${{ github.event.pull_request.base.ref }}"
          echo "head: ${{ github.event.pull_request.head.ref }}"
''';

  Future<List<MalformedRequestFile>> pullLatestToActiveCollection({
    required String branch,
    String? commitMessage,
  }) async {
    final git = _getActiveGitConnection();
    final pull = await api.pullCollectionAtBranchHead(
      owner: git.owner,
      repo: git.repo,
      branch: branch,
    );

    final activeCollection = _getActiveCollection();
    final import = _serializer.fromGitFiles(
      files: pull.files,
      fallbackCollectionId: activeCollection.id,
      fallbackCollectionName: activeCollection.name,
    );

    final malformed = await ref
        .read(collectionStateNotifierProvider.notifier)
        .replaceActiveCollectionFromGit(
          remoteCollection: import.collection,
          requestOrder: import.collection.requestIds,
          requestsById: import.requestsById,
          malformedRequests: import.malformedRequests,
        );

    await ref.read(environmentsStateNotifierProvider.notifier).importEnvironmentsFromGit(
          environmentsById: import.environmentsById,
          environmentOrder: import.environmentOrder,
        );

    final remoteActiveEnv = import.collection.activeEnvironmentId;
    if (remoteActiveEnv != null && remoteActiveEnv.isNotEmpty) {
      await ref.read(settingsProvider.notifier).update(
            activeEnvironmentId: remoteActiveEnv,
          );
    }

    final updatedGit = git.copyWith(
      branch: branch,
      lastSyncedCommitSha: pull.commitSha,
      lastPulledAt: DateTime.now(),
    );
    await ref
        .read(collectionStateNotifierProvider.notifier)
        .setActiveCollectionGitConnection(updatedGit);

    return malformed;
  }

  Future<List<MalformedRequestFile>> rollbackActiveCollectionToCommit({
    required String commitSha,
    required String branch,
  }) async {
    final git = _getActiveGitConnection();
    final pull = await api.pullCollectionAtCommit(
      owner: git.owner,
      repo: git.repo,
      commitSha: commitSha,
    );

    final activeCollection = _getActiveCollection();
    final import = _serializer.fromGitFiles(
      files: pull.files,
      fallbackCollectionId: activeCollection.id,
      fallbackCollectionName: activeCollection.name,
    );

    final malformed = await ref
        .read(collectionStateNotifierProvider.notifier)
        .replaceActiveCollectionFromGit(
          remoteCollection: import.collection,
          requestOrder: import.collection.requestIds,
          requestsById: import.requestsById,
          malformedRequests: import.malformedRequests,
        );

    await ref.read(environmentsStateNotifierProvider.notifier).importEnvironmentsFromGit(
          environmentsById: import.environmentsById,
          environmentOrder: import.environmentOrder,
        );

    final remoteActiveEnv = import.collection.activeEnvironmentId;
    if (remoteActiveEnv != null && remoteActiveEnv.isNotEmpty) {
      await ref.read(settingsProvider.notifier).update(
            activeEnvironmentId: remoteActiveEnv,
          );
    }

    final updatedGit = git.copyWith(
      branch: branch,
      lastSyncedCommitSha: pull.commitSha,
      lastPulledAt: DateTime.now(),
    );
    await ref
        .read(collectionStateNotifierProvider.notifier)
        .setActiveCollectionGitConnection(updatedGit);

    return malformed;
  }

  Future<({String? headSha, List<CommitInfo> commits})> loadHistory({
    required String branch,
  }) async {
    final git = _getActiveGitConnection();
    String? headSha;
    try {
      headSha = await api.getBranchHeadSha(
        owner: git.owner,
        repo: git.repo,
        branch: branch,
      );
    } on GitHubApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 409) rethrow;
      return (headSha: null, commits: const <CommitInfo>[]);
    }
    final commits = await api.getCommitHistory(
      owner: git.owner,
      repo: git.repo,
      branch: branch,
      perPage: 30,
    );
    return (headSha: headSha, commits: commits);
  }

  Future<List<BranchInfo>> loadBranches() async {
    final git = _getActiveGitConnection();
    return api.listBranches(owner: git.owner, repo: git.repo);
  }
}

enum PushChangeType { added, modified, deleted }

class PushFileChange {
  const PushFileChange({
    required this.path,
    required this.type,
  });

  final String path;
  final PushChangeType type;
}

class PushPreview {
  const PushPreview({
    required this.changes,
  });

  final List<PushFileChange> changes;

  int get addedCount =>
      changes.where((c) => c.type == PushChangeType.added).length;
  int get modifiedCount =>
      changes.where((c) => c.type == PushChangeType.modified).length;
  int get deletedCount =>
      changes.where((c) => c.type == PushChangeType.deleted).length;
}

