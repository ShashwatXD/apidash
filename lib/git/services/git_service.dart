import 'dart:convert';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/git/git_error.dart';
import 'package:path/path.dart' as p;

import '../models/git_models.dart';

const kGitIgnoreTemplate = '''
environments/*.local.json
oauth2_credentials.json
.apidash/local/
history/
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
      final porcelain = await _git(
        workspacePath,
        ['status', '--porcelain=v1', '-z', '-uall'],
      );
      final changes = _parsePorcelain(porcelain.stdout.toString());
      final hasCommits = await _hasLocalCommits(workspacePath);
      final (ahead, behind) = await _aheadBehind(workspacePath);
      final syncState = _syncState(
        changes: changes,
        ahead: ahead,
        behind: behind,
        hasRemote: remoteUrl != null,
        hasCommits: hasCommits,
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
    try {
      await _git(workspacePath, ['pull', '--no-rebase', 'origin', branch]);
    } catch (_) {
      if (await _isMergeInProgress(workspacePath)) {
        await _git(workspacePath, ['merge', '--abort'], allowFailure: true);
      }
      rethrow;
    }
  }

  Future<bool> _isMergeInProgress(String workspacePath) async {
    final result = await _git(
      workspacePath,
      ['rev-parse', '-q', 'MERGE_HEAD'],
      allowFailure: true,
    );
    return result.exitCode == 0;
  }

  Future<void> fetch(String workspacePath) async {
    await _git(workspacePath, ['fetch', 'origin']);
  }

  /// Returns the contents of a git [object] (e.g. `HEAD:path`, `:path`)
  /// in [workspacePath], or null when it cannot be read.
  Future<String?> showObject(String workspacePath, String object) async {
    final result = await _git(
      workspacePath,
      ['show', object],
      allowFailure: true,
    );
    if (result.exitCode != 0) return null;
    final text = result.stdout.toString();
    return text.isEmpty ? null : text;
  }

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
      environment: _gitEnv,
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
    final local = await _branchNames(
      workspacePath,
      ['branch', '--format=%(refname:short)'],
    );
    final remote = await _branchNames(
      workspacePath,
      ['branch', '-r', '--format=%(refname:short)'],
    );
    final names = <String>{...local};
    for (final ref in remote) {
      if (ref == 'origin/HEAD' || ref.endsWith('/HEAD')) continue;
      final slash = ref.indexOf('/');
      if (slash == -1) continue;
      names.add(ref.substring(slash + 1));
    }
    final sorted = names.toList()..sort();
    return sorted;
  }

  Future<List<String>> _branchNames(
    String workspacePath,
    List<String> args,
  ) async {
    final result = await _git(workspacePath, args, allowFailure: true);
    if (result.exitCode != 0) return const [];
    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<String> diffPath(String workspacePath, GitChange change) async {
    final relativePath = change.path;

    if (change.type == GitChangeType.deleted) {
      final result = await _git(
        workspacePath,
        ['diff', 'HEAD', '--', relativePath],
        allowFailure: true,
      );
      return result.stdout.toString();
    }

    if (change.type == GitChangeType.untracked) {
      return _syntheticAdditionDiff(workspacePath, relativePath);
    }

    final headDiff = await _git(
      workspacePath,
      ['diff', 'HEAD', '--', relativePath],
      allowFailure: true,
    );
    if (headDiff.stdout.toString().isNotEmpty) {
      return headDiff.stdout.toString();
    }

    final stagedDiff = await _git(
      workspacePath,
      ['diff', '--cached', '--', relativePath],
      allowFailure: true,
    );
    if (stagedDiff.stdout.toString().isNotEmpty) {
      return stagedDiff.stdout.toString();
    }

    if (change.type == GitChangeType.added ||
        change.type == GitChangeType.untracked ||
        !await _existsInHead(workspacePath, relativePath)) {
      return _syntheticAdditionDiff(workspacePath, relativePath);
    }

    return '';
  }

  Future<bool> _existsInHead(String workspacePath, String relativePath) async {
    final result = await _git(
      workspacePath,
      ['cat-file', '-e', 'HEAD:$relativePath'],
      allowFailure: true,
    );
    return result.exitCode == 0;
  }

  Future<String> _syntheticAdditionDiff(
    String workspacePath,
    String relativePath,
  ) async {
    final file = File(p.join(workspacePath, relativePath));
    if (!await file.exists()) return '';
    final lines = await file.readAsLines();
    if (lines.isEmpty) return '+\n';
    return lines.map((line) => '+$line').join('\n');
  }

  Future<void> checkoutBranch(String workspacePath, String branch) async {
    final trimmed = branch.trim();
    if (trimmed.isEmpty) {
      throw StateError('Branch name cannot be empty');
    }
    await _git(workspacePath, ['checkout', trimmed]);
  }

  Future<void> restoreToCommit(String workspacePath, String commitHash) async {
    final trimmed = commitHash.trim();
    if (trimmed.isEmpty) {
      throw StateError('Commit hash cannot be empty');
    }
    await _git(workspacePath, ['reset', '--hard', trimmed]);
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
      environment: _gitEnv,
    );
    if (!allowFailure && result.exitCode != 0) {
      final stderr = result.stderr.toString().trim();
      final stdout = result.stdout.toString().trim();
      throw StateError(gitCommandFailureMessage(stderr, stdout));
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
    final result = await _runProcess(
      'git',
      ['ls-remote', '--symref', 'origin', 'HEAD'],
      workingDirectory: workspacePath,
      environment: _gitEnv,
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => ProcessResult(0, 1, '', 'timed out'),
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
    final abbrev = await _git(
      workspacePath,
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      allowFailure: true,
    );
    if (abbrev.exitCode == 0) {
      final branch = abbrev.stdout.toString().trim();
      if (branch.isNotEmpty && branch != 'HEAD') {
        return branch;
      }
    }

    final symbolic = await _git(
      workspacePath,
      ['symbolic-ref', '--short', 'HEAD'],
      allowFailure: true,
    );
    if (symbolic.exitCode == 0) {
      final branch = symbolic.stdout.toString().trim();
      if (branch.isNotEmpty) return branch;
    }

    return null;
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

  Future<String?> _resolveRemoteTrackingRef(String workspacePath) async {
    final branch = await _currentBranch(workspacePath);
    if (branch != null && branch != 'HEAD') {
      final ref = 'origin/$branch';
      final exists = await _git(
        workspacePath,
        ['rev-parse', '--verify', ref],
        allowFailure: true,
      );
      if (exists.exitCode == 0) return ref;
    }

    return null;
  }

  Future<(int ahead, int behind)> _aheadBehind(String workspacePath) async {
    final upstream = await _git(
      workspacePath,
      ['rev-list', '--left-right', '--count', '@{u}...HEAD'],
      allowFailure: true,
    );
    if (upstream.exitCode == 0) {
      return _parseAheadBehind(upstream.stdout.toString());
    }

    final remoteRef = await _resolveRemoteTrackingRef(workspacePath);
    if (remoteRef == null) {
      return _localCommitCount(workspacePath);
    }

    if (!await _hasLocalCommits(workspacePath)) {
      final behind = await _remoteCommitCount(workspacePath, remoteRef);
      return (0, behind);
    }

    final vsRemote = await _git(
      workspacePath,
      ['rev-list', '--left-right', '--count', '$remoteRef...HEAD'],
      allowFailure: true,
    );
    if (vsRemote.exitCode == 0) {
      return _parseAheadBehind(vsRemote.stdout.toString());
    }

    return (0, 0);
  }

  (int ahead, int behind) _parseAheadBehind(String output) {
    final parts = output.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return (0, 0);
    return (int.tryParse(parts[1]) ?? 0, int.tryParse(parts[0]) ?? 0);
  }

  Future<(int ahead, int behind)> _localCommitCount(String workspacePath) async {
    final result = await _git(
      workspacePath,
      ['rev-list', '--count', 'HEAD'],
      allowFailure: true,
    );
    if (result.exitCode != 0) return (0, 0);
    final count = int.tryParse(result.stdout.toString().trim()) ?? 0;
    return (count, 0);
  }

  Future<int> _remoteCommitCount(String workspacePath, String remoteRef) async {
    final result = await _git(
      workspacePath,
      ['rev-list', '--count', remoteRef],
      allowFailure: true,
    );
    if (result.exitCode != 0) return 0;
    return int.tryParse(result.stdout.toString().trim()) ?? 0;
  }

  GitSyncState _syncState({
    required List<GitChange> changes,
    required int ahead,
    required int behind,
    required bool hasRemote,
    required bool hasCommits,
  }) {
    final dirty = changes.isNotEmpty;
    if (!hasRemote) {
      if (!hasCommits) return GitSyncState.noUpstream;
      return dirty ? GitSyncState.dirty : GitSyncState.noUpstream;
    }
    if (ahead > 0 && behind > 0) return GitSyncState.diverged;
    if (behind > 0) return dirty ? GitSyncState.dirty : GitSyncState.behind;
    if (ahead > 0) return GitSyncState.ahead;
    return dirty ? GitSyncState.dirty : GitSyncState.clean;
  }

  String _normalizeChangePath(String path) {
    return path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
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
      final type = _changeType(indexStatus, workTreeStatus);

      if (type == GitChangeType.renamed) {
        i++;
        if (i < records.length && records[i].isNotEmpty) {
          path = records[i];
        }
      }

      path = _normalizeChangePath(path);
      if (path.isEmpty) {
        i++;
        continue;
      }

      changes.add(
        GitChange(
          path: path,
          type: type,
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
