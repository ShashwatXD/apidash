import 'package:apidash/consts.dart';

import 'git_models.dart';

class GitFolderSummary {
  const GitFolderSummary({
    required this.counts,
    this.entityRemoved = false,
    this.entityAdded = false,
  });

  final Map<GitChangeType, int> counts;


  final bool entityRemoved;

  final bool entityAdded;

  int get fileCount => counts.values.fold(0, (sum, n) => sum + n);

  bool get isEmpty => fileCount == 0;

  bool get isUniformDeleted => entityRemoved;

  bool get isUniformAdded => entityAdded;

  bool get isUniform =>
      isUniformDeleted ||
      isUniformAdded ||
      (fileCount > 0 &&
          counts.length == 1 &&
          (counts.containsKey(GitChangeType.modified) ||
              counts.containsKey(GitChangeType.renamed)));

  GitChangeType? get uniformType {
    if (isUniformDeleted) return GitChangeType.deleted;
    if (isUniformAdded) {
      if (counts.containsKey(GitChangeType.untracked)) {
        return GitChangeType.untracked;
      }
      return GitChangeType.added;
    }
    if (!isUniform || counts.length != 1) return null;
    return counts.keys.first;
  }

  /// Stable badge order for the folder row.
  List<GitChangeType> get badgeTypes {
    const order = [
      GitChangeType.added,
      GitChangeType.untracked,
      GitChangeType.modified,
      GitChangeType.renamed,
      GitChangeType.deleted,
    ];
    return [
      for (final type in order)
        if ((counts[type] ?? 0) > 0) type,
    ];
  }
}

String? gitFolderIdentityFileName(String folderPath) {
  final parts =
      folderPath.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length == 2 && parts[0] == kWorkspaceCollectionsDir) {
    return kWorkspaceRequestIndexFile;
  }
  if (parts.length == 3 && parts[0] == kWorkspaceCollectionsDir) {
    return kWorkspaceRequestFile;
  }
  if (parts.length == 2 && parts[0] == kWorkspaceEnvironmentsDir) {
    return '${parts[1]}$kJsonFileExtension';
  }
  return null;
}

class GitTreeNode {
  GitTreeNode.folder({
    required this.name,
    required this.path,
    List<GitTreeNode>? children,
    GitFolderSummary? summary,
  })  : isFile = false,
        change = null,
        children = children ?? [],
        summary = summary ??
            summarizeGitFolderChildren(
              folderPath: path,
              children: children ?? const [],
            );

  GitTreeNode.file({
    required this.name,
    required this.path,
    required this.change,
  })  : isFile = true,
        children = const [],
        summary = null;

  final String name;
  final String path;
  final bool isFile;
  final GitChange? change;
  final List<GitTreeNode> children;

  final GitFolderSummary? summary;

  bool get showsChangeBadges =>
      !isFile && gitFolderIdentityFileName(path) != null;

  Iterable<String> get filePaths sync* {
    if (isFile) {
      yield path;
      return;
    }
    for (final child in children) {
      yield* child.filePaths;
    }
  }

  Iterable<GitChange> get descendantChanges sync* {
    if (isFile) {
      if (change != null) yield change!;
      return;
    }
    for (final child in children) {
      yield* child.descendantChanges;
    }
  }

  /// Label shown in the tree. Full entity add/delete only when the identity
  /// file confirms it — so a still-present collection is never labeled deleted
  /// just because some nested files were removed.
  String get displayLabel {
    if (isFile) return name;
    final folder = summary;
    if (folder == null || folder.isEmpty) return name;
    if (folder.isUniformDeleted) return '$name (deleted)';
    if (folder.isUniformAdded) return '$name (added)';
    return name;
  }

  /// Best leaf change to preview when the user selects a folder row.
  ///
  /// Prefers files directly under this folder (e.g. indexes) over nested
  /// request files so tapping `collections/` previews the collections index.
  GitChange? get representativeChange {
    if (isFile) return change;
    final changes = descendantChanges.toList();
    if (changes.isEmpty) return null;

    final directPrefix = '$path/';
    bool isDirectChild(String changePath) {
      if (!changePath.startsWith(directPrefix)) return false;
      return !changePath.substring(directPrefix.length).contains('/');
    }

    int score(GitChange c) {
      final base = c.path.split('/').last;
      var rank = switch (base) {
        kWorkspaceCollectionsIndexFile ||
        kWorkspaceEnvironmentIndexFile =>
          0,
        kWorkspaceRequestIndexFile => 1,
        kWorkspaceRequestFile => 2,
        kWorkspaceResponseFile => 3,
        _ => 4,
      };
      if (!isDirectChild(c.path)) {
        rank += 10;
      }
      return rank;
    }

    changes.sort((a, b) {
      final byScore = score(a).compareTo(score(b));
      if (byScore != 0) return byScore;
      return a.path.compareTo(b.path);
    });
    return changes.first;
  }
}

GitFolderSummary summarizeGitFolderChildren({
  required String folderPath,
  required List<GitTreeNode> children,
}) {
  final counts = <GitChangeType, int>{};

  void add(GitChangeType type) {
    counts[type] = (counts[type] ?? 0) + 1;
  }

  void walk(GitTreeNode node) {
    if (node.isFile) {
      final change = node.change;
      if (change != null) add(change.type);
      return;
    }
    final nested = node.summary;
    if (nested != null && nested.counts.isNotEmpty) {
      for (final entry in nested.counts.entries) {
        counts[entry.key] = (counts[entry.key] ?? 0) + entry.value;
      }
      return;
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  for (final child in children) {
    walk(child);
  }

  final identity = gitFolderIdentityFileName(folderPath);
  var entityRemoved = false;
  var entityAdded = false;
  if (identity != null) {
    for (final child in children) {
      if (!child.isFile || child.name != identity) continue;
      final type = child.change?.type;
      if (type == GitChangeType.deleted) {
        entityRemoved = true;
      } else if (type == GitChangeType.added ||
          type == GitChangeType.untracked) {
        entityAdded = true;
      }
    }
  }

  // Identity deleted but other files under the folder were added/modified —
  // treat as mixed, not a clean entity removal.
  final hasNonDelete = counts.entries.any(
    (e) =>
        e.value > 0 &&
        e.key != GitChangeType.deleted,
  );
  if (entityRemoved && hasNonDelete) {
    entityRemoved = false;
  }

  final hasNonAdd = counts.entries.any(
    (e) =>
        e.value > 0 &&
        e.key != GitChangeType.added &&
        e.key != GitChangeType.untracked,
  );
  if (entityAdded && hasNonAdd) {
    entityAdded = false;
  }

  return GitFolderSummary(
    counts: counts,
    entityRemoved: entityRemoved,
    entityAdded: entityAdded,
  );
}

List<GitTreeNode> buildGitChangeTree(List<GitChange> changes) {
  if (changes.isEmpty) return const [];

  final root = <String, _MutableNode>{};

  for (final change in changes) {
    final parts =
        change.path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    var level = root;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;
      final fullPath = parts.sublist(0, i + 1).join('/');
      level.putIfAbsent(
        part,
        () => _MutableNode(name: part, path: fullPath, isFile: isLast),
      );
      final node = level[part]!;
      if (isLast) {
        node.isFile = true;
        node.change = change;
      } else {
        level = node.children;
      }
    }
  }

  List<GitTreeNode> toNodes(Map<String, _MutableNode> map) {
    final nodes = map.values.toList()
      ..sort((a, b) {
        if (a.isFile != b.isFile) return a.isFile ? 1 : -1;
        return a.name.compareTo(b.name);
      });
    return [
      for (final node in nodes)
        node.isFile
            ? GitTreeNode.file(
                name: node.name,
                path: node.path,
                change: node.change!,
              )
            : GitTreeNode.folder(
                name: node.name,
                path: node.path,
                children: toNodes(node.children),
              ),
    ];
  }

  return toNodes(root);
}

class _MutableNode {
  _MutableNode({
    required this.name,
    required this.path,
    required this.isFile,
  });

  final String name;
  final String path;
  bool isFile;
  GitChange? change;
  final Map<String, _MutableNode> children = {};
}

bool? folderSelectionState(GitTreeNode folder, Set<String> selectedPaths) {
  final paths = folder.filePaths.toList();
  if (paths.isEmpty) return false;
  final selected = paths.where(selectedPaths.contains).length;
  if (selected == 0) return false;
  if (selected == paths.length) return true;
  return null;
}
