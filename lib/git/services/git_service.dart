import 'dart:convert';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:path/path.dart' as p;

import '../models/git_models.dart';

const kGitIgnoreTemplate = '''
environments/*.local.json
oauth2_credentials.json
.apidash/local/
history/
collections/**/requests/**/response.json
*.tmp
.DS_Store
Thumbs.db
''';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

class GitService {
  GitService({ProcessRunner? processRunner})
      : _runProcess = processRunner ?? Process.run;

  final ProcessRunner _runProcess;

  Future<bool> isGitInstalled() async {
    try {
      final result = await _runProcess('git', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<GitStatus> getStatus(String workspacePath) async {
    if (!await isGitInstalled()) {
      return GitStatus.noGit();
    }
    if (!await isRepository(workspacePath)) {
      return const GitStatus(syncState: GitSyncState.notRepo);
    }

    try {
      final branch = await _currentBranch(workspacePath);
      final remoteUrl = await _remoteUrl(workspacePath);
      final porcelain = await _git(workspacePath, ['status', '--porcelain=v1', '-z']);
      final changes = _parsePorcelain(porcelain.stdout.toString());
      final (ahead, behind) = await _aheadBehind(workspacePath);
      final syncState = _syncState(
        changes: changes,
        ahead: ahead,
        behind: behind,
        hasRemote: remoteUrl != null,
      );
      final logResult = await _git(
        workspacePath,
        [
          'log',
          '-n',
          '10',
          r'--format=%H%x00%s%x00%an%x00%ar',
        ],
        allowFailure: true,
      );
      final recentCommits = logResult.exitCode == 0
          ? _parseLog(logResult.stdout.toString())
          : const <GitLogEntry>[];
      final branches = await listBranches(workspacePath);

      return GitStatus(
        branch: branch,
        syncState: syncState,
        remoteUrl: remoteUrl,
        ahead: ahead,
        behind: behind,
        changes: changes,
        recentCommits: recentCommits,
        branches: branches,
        isRepository: true,
      );
    } catch (e) {
      return GitStatus(
        isRepository: true,
        syncState: GitSyncState.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<bool> isRepository(String workspacePath) async {
    try {
      final result = await _git(
        workspacePath,
        ['rev-parse', '--is-inside-work-tree'],
        allowFailure: true,
      );
      return result.exitCode == 0 &&
          result.stdout.toString().trim().toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> initRepository(String workspacePath) async {
    await _git(workspacePath, ['init']);
    final gitignore = File(p.join(workspacePath, '.gitignore'));
    if (!await gitignore.exists()) {
      await gitignore.writeAsString(kGitIgnoreTemplate);
    }
  }

  Future<void> setRemoteUrl(String workspacePath, String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw StateError('Remote URL cannot be empty');
    }
    final existing = await _remoteUrl(workspacePath);
    if (existing == null) {
      await _git(workspacePath, ['remote', 'add', 'origin', trimmed]);
    } else {
      await _git(workspacePath, ['remote', 'set-url', 'origin', trimmed]);
    }
  }

  Future<void> stage(String workspacePath, List<String> paths) async {
    if (paths.isEmpty) return;
    await _git(workspacePath, ['add', '--', ...paths]);
  }

  Future<void> commit(String workspacePath, String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      throw StateError('Commit message cannot be empty');
    }
    await _git(workspacePath, ['commit', '-m', trimmed]);
  }

  Future<void> pull(String workspacePath) async {
    final branch = await _resolvePullBranch(workspacePath);
    if (branch == null) {
      throw StateError(
        'Cannot pull: not on a branch and could not detect the remote default branch',
      );
    }
    if (!await _hasLocalCommits(workspacePath)) {
      await _git(workspacePath, ['fetch', 'origin', branch]);
      await _git(
        workspacePath,
        ['checkout', '-f', '-B', branch, 'origin/$branch'],
      );
      return;
    }
    await _git(workspacePath, ['pull', 'origin', branch]);
  }

  bool looksLikeCloneUrl(String url) => looksLikeGitRemoteUrl(url);

  Future<bool> validateCloneUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty || !looksLikeGitRemoteUrl(trimmed)) return false;
    if (!await isGitInstalled()) return false;
    if (!await _lsRemoteReachable(trimmed)) return false;
    return _remoteHasApidashWorkspace(trimmed);
  }

  Future<bool> _lsRemoteReachable(String url) async {
    try {
      final result = await _runProcess(
        'git',
        ['ls-remote', '--exit-code', url, 'HEAD'],
        environment: _gitEnv,
      ).timeout(const Duration(seconds: 12));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _remoteHasApidashWorkspace(String url) async {
    final tempDir = await Directory.systemTemp.createTemp('apidash-git-validate-');
    try {
      if (!await _runGitIn(tempDir.path, ['init'])) return false;
      if (!await _runGitIn(tempDir.path, ['remote', 'add', 'origin', url])) {
        return false;
      }
      if (!await _runGitIn(
        tempDir.path,
        ['fetch', '--depth', '1', 'origin', 'HEAD'],
        timeout: const Duration(seconds: 20),
      )) {
        return false;
      }

      final collectionsIndexPath = p.posix.join(
        kWorkspaceCollectionsDir,
        kWorkspaceCollectionsIndexFile,
      );
      final environmentsIndexPath = p.posix.join(
        kWorkspaceEnvironmentsDir,
        kWorkspaceEnvironmentIndexFile,
      );

      final tree = await _runProcess(
        'git',
        ['ls-tree', '-r', '--name-only', 'FETCH_HEAD'],
        workingDirectory: tempDir.path,
        environment: _gitEnv,
      );
      if (tree.exitCode != 0) return false;

      final paths = tree.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toSet();
      if (!paths.contains(collectionsIndexPath) ||
          !paths.contains(environmentsIndexPath)) {
        return false;
      }

      final collectionsJson =
          await _gitShow(tempDir.path, 'FETCH_HEAD:$collectionsIndexPath');
      final environmentsJson =
          await _gitShow(tempDir.path, 'FETCH_HEAD:$environmentsIndexPath');
      if (collectionsJson == null || environmentsJson == null) return false;

      return parseApidashWorkspaceIndices(
        collectionsIndexJson: collectionsJson,
        environmentsIndexJson: environmentsJson,
      );
    } catch (_) {
      return false;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<bool> _runGitIn(
    String repoPath,
    List<String> args, {
    Duration? timeout,
  }) async {
    try {
      final future = _runProcess(
        'git',
        args,
        workingDirectory: repoPath,
        environment: _gitEnv,
      );
      final result = timeout != null
          ? await future.timeout(timeout)
          : await future;
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _gitShow(String repoPath, String object) async {
    final result = await _runProcess(
      'git',
      ['show', object],
      workingDirectory: repoPath,
      environment: _gitEnv,
    );
    if (result.exitCode != 0) return null;
    final text = result.stdout.toString();
    return text.isEmpty ? null : text;
  }

  Map<String, String> get _gitEnv => {
        ...Platform.environment,
        'GIT_TERMINAL_PROMPT': '0',
      };

  /// Clones [remoteUrl] into [parentDirectory]. Returns the new workspace path.
  Future<String> clone(String remoteUrl, String parentDirectory) async {
    final trimmed = remoteUrl.trim();
    if (trimmed.isEmpty) {
      throw StateError('Remote URL cannot be empty');
    }
    final parent = p.normalize(parentDirectory);
    if (!await Directory(parent).exists()) {
      throw StateError('Parent directory does not exist');
    }
    final repoName = repoNameFromCloneUrl(trimmed);
    final targetPath = p.join(parent, repoName);
    if (await Directory(targetPath).exists()) {
      throw StateError('Folder already exists: $targetPath');
    }
    final result = await _runProcess(
      'git',
      ['clone', trimmed, repoName],
      workingDirectory: parent,
      environment: {
        ...Platform.environment,
        'GIT_TERMINAL_PROMPT': '0',
      },
    );
    if (result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      throw StateError(
        stderr.isNotEmpty ? stderr : stdout.isNotEmpty ? stdout : 'git clone failed',
      );
    }
    return targetPath;
  }

  Future<List<String>> listBranches(String workspacePath) async {
    final result = await _git(
      workspacePath,
      ['branch', '--format=%(refname:short)'],
      allowFailure: true,
    );
    if (result.exitCode != 0) return const [];
    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<void> checkoutBranch(String workspacePath, String branch) async {
    final trimmed = branch.trim();
    if (trimmed.isEmpty) {
      throw StateError('Branch name cannot be empty');
    }
    await _git(workspacePath, ['checkout', trimmed]);
  }

  Future<void> push(String workspacePath) async {
    final branch = await _currentBranch(workspacePath);
    if (branch == null || branch == 'HEAD') {
      throw StateError('Cannot push: not on a branch');
    }
    final upstream = await _git(
      workspacePath,
      ['rev-parse', '--abbrev-ref', '@{upstream}'],
      allowFailure: true,
    );
    if (upstream.exitCode != 0) {
      await _git(workspacePath, ['push', '-u', 'origin', branch]);
    } else {
      await _git(workspacePath, ['push', 'origin', branch]);
    }
  }

  Future<ProcessResult> _git(
    String workspacePath,
    List<String> args, {
    bool allowFailure = false,
  }) async {
    final result = await _runProcess(
      'git',
      args,
      workingDirectory: workspacePath,
      environment: {
        ...Platform.environment,
        'GIT_TERMINAL_PROMPT': '0',
      },
    );
    if (!allowFailure && result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      throw StateError(
        stderr.isNotEmpty ? stderr : stdout.isNotEmpty ? stdout : 'git ${args.first} failed',
      );
    }
    return result;
  }

  Future<bool> _hasLocalCommits(String workspacePath) async {
    final result = await _git(
      workspacePath,
      ['rev-parse', 'HEAD'],
      allowFailure: true,
    );
    return result.exitCode == 0;
  }

  Future<String?> _resolvePullBranch(String workspacePath) async {
    final branch = await _currentBranch(workspacePath);
    if (branch != null && branch != 'HEAD') return branch;
    return _defaultRemoteBranch(workspacePath);
  }

  Future<String?> _defaultRemoteBranch(String workspacePath) async {
    final result = await _git(
      workspacePath,
      ['ls-remote', '--symref', 'origin', 'HEAD'],
      allowFailure: true,
    );
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n')) {
      final match =
          RegExp(r'^ref: refs/heads/(.+)\tHEAD$').firstMatch(line.trim());
      if (match != null) return match.group(1);
    }
    return null;
  }

  Future<String?> _currentBranch(String workspacePath) async {
    final result = await _git(
      workspacePath,
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      allowFailure: true,
    );
    if (result.exitCode != 0) return null;
    final branch = result.stdout.toString().trim();
    return branch.isEmpty ? null : branch;
  }

  Future<String?> _remoteUrl(String workspacePath) async {
    final result = await _git(
      workspacePath,
      ['remote', 'get-url', 'origin'],
      allowFailure: true,
    );
    if (result.exitCode != 0) return null;
    final url = result.stdout.toString().trim();
    return url.isEmpty ? null : url;
  }

  Future<(int ahead, int behind)> _aheadBehind(String workspacePath) async {
    final result = await _git(
      workspacePath,
      ['rev-list', '--left-right', '--count', '@{u}...HEAD'],
      allowFailure: true,
    );
    if (result.exitCode != 0) return (0, 0);
    final parts = result.stdout.toString().trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return (0, 0);
    return (int.tryParse(parts[1]) ?? 0, int.tryParse(parts[0]) ?? 0);
  }

  GitSyncState _syncState({
    required List<GitChange> changes,
    required int ahead,
    required int behind,
    required bool hasRemote,
  }) {
    final dirty = changes.isNotEmpty;
    if (!hasRemote) {
      return dirty ? GitSyncState.dirty : GitSyncState.noUpstream;
    }
    if (ahead > 0 && behind > 0) return GitSyncState.diverged;
    if (behind > 0) return dirty ? GitSyncState.dirty : GitSyncState.behind;
    if (ahead > 0) return GitSyncState.ahead;
    return dirty ? GitSyncState.dirty : GitSyncState.clean;
  }

  List<GitChange> _parsePorcelain(String output) {
    if (output.isEmpty) return const [];
    final changes = <GitChange>[];
    final records = output.split('\x00');
    int i = 0;
    while (i < records.length) {
      final record = records[i];
      if (record.length < 3) {
        i++;
        continue;
      }
      final indexStatus = record[0];
      final workTreeStatus = record[1];
      var path = record.substring(3);
      final staged = indexStatus != ' ' && indexStatus != '?';
      final type = _changeType(indexStatus, workTreeStatus);

      if (type == GitChangeType.renamed) {
        i++;
        if (i < records.length && records[i].isNotEmpty) {
          path = records[i];
        }
      }

      changes.add(
        GitChange(
          path: path,
          type: type,
          staged: staged,
        ),
      );
      i++;
    }
    return changes;
  }

  GitChangeType _changeType(String index, String workTree) {
    if (index == '?' && workTree == '?') return GitChangeType.untracked;
    if (index == 'D' || workTree == 'D') return GitChangeType.deleted;
    if (index == 'A' || workTree == 'A') return GitChangeType.added;
    if (index == 'R' || workTree == 'R') return GitChangeType.renamed;
    return GitChangeType.modified;
  }

  List<GitLogEntry> _parseLog(String output) {
    if (output.isEmpty) return const [];
    final entries = <GitLogEntry>[];
    for (final line in output.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\x00');
      if (parts.length < 4) continue;
      entries.add(
        GitLogEntry(
          hash: parts[0],
          message: parts[1],
          author: parts[2],
          relativeTime: parts[3],
        ),
      );
    }
    return entries;
  }
}

String repoNameFromCloneUrl(String url) {
  var trimmed = url.trim();
  if (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  if (trimmed.endsWith('.git')) {
    trimmed = trimmed.substring(0, trimmed.length - 4);
  }
  final colonIndex = trimmed.lastIndexOf(':');
  if (colonIndex != -1 && !trimmed.contains('://')) {
    trimmed = trimmed.substring(colonIndex + 1);
  }
  return p.basename(trimmed);
}

/// Returns true when index files look like API Dash workspace catalogs.
bool parseApidashWorkspaceIndices({
  required String collectionsIndexJson,
  required String environmentsIndexJson,
}) {
  try {
    final collections = jsonDecode(collectionsIndexJson);
    final environments = jsonDecode(environmentsIndexJson);
    if (collections is! Map || environments is! Map) return false;
    if (collections[kWorkspaceCollectionsIndexKey] is! List) return false;
    if (environments[kWorkspaceEnvironmentIdsKey] is! List) return false;
    return true;
  } catch (_) {
    return false;
  }
}

bool looksLikeGitRemoteUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('https://') || trimmed.startsWith('http://')) {
    return trimmed.length > 8;
  }
  if (trimmed.startsWith('ssh://')) return trimmed.length > 6;
  if (trimmed.startsWith('git@') && trimmed.contains(':')) return true;
  return false;
}
