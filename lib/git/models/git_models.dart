enum GitChangeType { added, modified, deleted, untracked, renamed }

enum GitSyncState { clean, dirty, ahead, behind, diverged, noUpstream, notRepo, noGit, error }

class GitChange {
  const GitChange({
    required this.path,
    required this.type,
  });

  final String path;
  final GitChangeType type;
}

class GitLogEntry {
  const GitLogEntry({
    required this.hash,
    required this.message,
    required this.author,
    required this.relativeTime,
  });

  final String hash;
  final String message;
  final String author;
  final String relativeTime;
}

class GitStatus {
  const GitStatus({
    this.branch,
    this.syncState = GitSyncState.notRepo,
    this.remoteUrl,
    this.ahead = 0,
    this.behind = 0,
    this.changes = const [],
    this.recentCommits = const [],
    this.branches = const [],
    this.isRepository = false,
    this.gitInstalled = true,
    this.errorMessage,
  });

  final String? branch;
  final GitSyncState syncState;
  final String? remoteUrl;
  final int ahead;
  final int behind;
  final List<GitChange> changes;
  final List<GitLogEntry> recentCommits;
  final List<String> branches;
  final bool isRepository;
  final bool gitInstalled;
  final String? errorMessage;

  static const empty = GitStatus();

  static GitStatus noGit() => const GitStatus(
        gitInstalled: false,
        syncState: GitSyncState.noGit,
        errorMessage: 'Git is not installed or not on PATH',
      );
}
