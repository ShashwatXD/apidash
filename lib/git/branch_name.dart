import 'package:apidash/git/consts.dart';

const kGitBranchNameMaxLength = 255;

/// Returns a user-facing error message, or null when [name] is valid.
String? validateGitBranchName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return kMsgGitBranchNameEmpty;
  }
  if (trimmed.length > kGitBranchNameMaxLength) {
    return kMsgGitBranchNameTooLong;
  }
  final upper = trimmed.toUpperCase();
  if (upper == 'HEAD' || upper == '@{HEAD}') {
    return kMsgGitBranchNameReserved;
  }
  if (trimmed.startsWith('.') ||
      trimmed.endsWith('.') ||
      trimmed.endsWith('.lock')) {
    return kMsgGitBranchNameInvalid;
  }
  if (trimmed.contains('..') ||
      trimmed.contains('//') ||
      trimmed.contains('@{')) {
    return kMsgGitBranchNameInvalid;
  }
  if (RegExp(r'[\s~^:?*\[\\]').hasMatch(trimmed)) {
    return kMsgGitBranchNameInvalid;
  }
  if (trimmed.startsWith('/') || trimmed.endsWith('/')) {
    return kMsgGitBranchNameInvalid;
  }
  return null;
}
