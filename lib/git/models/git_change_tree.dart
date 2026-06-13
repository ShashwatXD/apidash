import 'git_models.dart';

class GitTreeNode {
  GitTreeNode.folder({
    required this.name,
    required this.path,
    List<GitTreeNode>? children,
  })  : isFile = false,
        change = null,
        children = children ?? [];

  GitTreeNode.file({
    required this.name,
    required this.path,
    required this.change,
  })  : isFile = true,
        children = const [];

  final String name;
  final String path;
  final bool isFile;
  final GitChange? change;
  final List<GitTreeNode> children;

  Iterable<String> get filePaths sync* {
    if (isFile) {
      yield path;
      return;
    }
    for (final child in children) {
      yield* child.filePaths;
    }
  }
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
