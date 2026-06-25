import 'package:apidash/consts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> resolveWorkspaceRoot({String? path}) async {
  if (path != null && path.isNotEmpty) {
    return path;
  }
  return null;
}

Future<String> resolveMobileWorkspacesParent() async {
  final documents = await getApplicationDocumentsDirectory();
  return p.join(documents.path, kMobileWorkspacesParentSubpath);
}

Future<String> resolveMobileWorkspacePath(String workspaceId) async {
  final parent = await resolveMobileWorkspacesParent();
  return p.join(parent, workspaceId);
}
