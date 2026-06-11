import 'dart:convert';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:path/path.dart' as p;

import 'git_models.dart';

const kGitIgnoreTemplate = '''# API Dash — local secrets and machine state
environments/*.local.json
oauth2_credentials.json
.apidash/local/

# Large / personal / noisy
history/
collections/**/requests/**/response.json

# Autosave / OS
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
      final changes = _parsePorcelain(
        porcelain.stdout.toString(),
        workspacePath,
      );
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

      return GitStatus(
        branch: branch,
        syncState: syncState,
        remoteUrl: remoteUrl,
        ahead: ahead,
        behind: behind,
        changes: changes,
        recentCommits: recentCommits,
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

  List<GitChange> _parsePorcelain(String output, String workspacePath) {
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
          displayName: resolveDisplayName(workspacePath, path),
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

String resolveDisplayName(String workspacePath, String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/');
  if (normalized == kWorkspaceMetaFile) return 'Workspace settings';
  if (normalized == 'collections/$kWorkspaceCollectionsIndexFile') {
    return 'Collections catalog';
  }
  if (normalized == 'environments/$kWorkspaceEnvironmentIndexFile') {
    return 'Environments catalog';
  }
  if (normalized == '.gitignore') return '.gitignore';

  if (RegExp(r'^collections/[^/]+/requests/[^/]+/request\.json$').hasMatch(normalized)) {
    return _requestLabel(workspacePath, normalized) ?? p.basename(p.dirname(normalized));
  }

  if (normalized.startsWith('environments/') && normalized.endsWith('.json')) {
    return _environmentLabel(workspacePath, normalized) ??
        p.basenameWithoutExtension(normalized);
  }

  if (normalized.endsWith('/$kWorkspaceCollectionFile')) {
    return _collectionLabel(workspacePath, normalized) ?? 'Collection metadata';
  }

  return p.basename(normalized);
}

String? _requestLabel(String workspacePath, String relativePath) {
  try {
    final file = File(p.join(workspacePath, relativePath));
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final http = json['httpRequestModel'];
    if (http is Map<String, dynamic>) {
      final method = http['method']?.toString() ?? '';
      final url = http['url']?.toString() ?? '';
      if (method.isNotEmpty || url.isNotEmpty) {
        return '${method.toUpperCase()} $url'.trim();
      }
    }
    final name = json['name']?.toString();
    if (name != null && name.isNotEmpty) return name;
  } catch (_) {}
  return null;
}

String? _environmentLabel(String workspacePath, String relativePath) {
  try {
    final file = File(p.join(workspacePath, relativePath));
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final name = json['name']?.toString();
    if (name != null && name.isNotEmpty) return name;
  } catch (_) {}
  return null;
}

String? _collectionLabel(String workspacePath, String relativePath) {
  try {
    final file = File(p.join(workspacePath, relativePath));
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final name = json['name']?.toString();
    if (name != null && name.isNotEmpty) return '$name (collection)';
  } catch (_) {}
  return null;
}
