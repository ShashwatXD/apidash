import 'dart:convert';
import 'dart:io';

/// Returns paths that contain non-empty secret values (unsafe to commit).
List<String> findUnsafeSecretEnvFiles(String workspacePath, Iterable<String> paths) {
  final unsafe = <String>[];
  for (final relative in paths) {
    final normalized = relative.replaceAll('\\', '/');
    if (!normalized.startsWith('environments/') || !normalized.endsWith('.json')) {
      continue;
    }
    if (normalized.contains('.local.')) continue;

    final file = File('$workspacePath${Platform.pathSeparator}$relative');
    if (!file.existsSync()) continue;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final values = json['values'];
      if (values is! List) continue;
      for (final entry in values) {
        if (entry is! Map) continue;
        final type = entry['type']?.toString();
        final value = entry['value']?.toString() ?? '';
        if (type == 'secret' && value.trim().isNotEmpty) {
          unsafe.add(relative);
          break;
        }
      }
    } catch (_) {
      // Skip unreadable files; git will surface other errors.
    }
  }
  return unsafe;
}
