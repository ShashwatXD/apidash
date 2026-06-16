import 'consts.dart';

String formatGitCollaborationError(Object error) {
  var msg = error.toString().trim();
  while (msg.startsWith('Bad state: ')) {
    msg = msg.substring('Bad state: '.length).trim();
  }

  final lower = msg.toLowerCase();
  if (lower.contains('failed to push some refs') ||
      lower.contains('non-fast-forward') ||
      (lower.contains('rejected') && lower.contains('fetch first'))) {
    return kMsgGitPushRejected;
  }
  if (lower.contains('reconcile divergent branches')) {
    return kMsgGitPullDivergent;
  }
  if (lower.contains('merge conflict') ||
      lower.contains('automatic merge failed')) {
    return kMsgGitMergeConflict;
  }
  if (lower.contains('unmerged files') ||
      lower.contains('unresolved conflict')) {
    return kMsgGitUnmergedFiles;
  }
  if (_isGitAuthError(lower)) {
    return kMsgGitAuthRequired;
  }

  return _singleGitErrorLine(msg);
}

bool _isGitAuthError(String lower) {
  if (lower.contains('authentication failed')) return true;
  if (lower.contains('could not read username')) return true;
  if (lower.contains('terminal prompts disabled')) return true;
  if (lower.contains('permission denied (publickey)')) return true;
  if (lower.contains('invalid username or password')) return true;
  if (lower.contains('support for password authentication was removed')) {
    return true;
  }
  if (lower.contains('could not authenticate')) return true;
  if (lower.contains('http 401') || lower.contains('401 unauthorized')) {
    return true;
  }
  if (lower.contains('repository not found')) return true;
  if (lower.contains('unable to access') &&
      (lower.contains('403') || lower.contains('401'))) {
    return true;
  }
  return false;
}

String _singleGitErrorLine(String msg) {
  for (final line in msg.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('hint:')) continue;
    if (_isGitProgressLine(lower)) continue;
    if (lower.startsWith('error:')) {
      return trimmed.substring('error:'.length).trim();
    }
    if (lower.startsWith('fatal:')) {
      return trimmed.substring('fatal:'.length).trim();
    }
    if (trimmed.contains('[rejected]')) return trimmed;
    return trimmed;
  }
  return msg;
}

bool _isGitProgressLine(String lower) {
  if (lower.startsWith('from ')) return true;
  if (lower.startsWith('*')) return true;
  if (lower.startsWith('remote:')) return true;
  if (lower.startsWith('auto-merging ')) return true;
  return false;
}

String gitCommandFailureMessage(String stderr, String stdout) {
  final combined = [stderr, stdout]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join('\n')
      .trim();
  return combined.isEmpty ? 'git command failed' : combined;
}
