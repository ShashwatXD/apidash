import 'package:apidash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Switches to Requests, expands the bottom integrated shell, and sets its cwd.
void focusIntegratedShell(WidgetRef ref, String workingDirectory) {
  final path = workingDirectory.trim();
  if (path.isEmpty) return;
  ref.read(shellTerminalCwdOverrideProvider.notifier).state = path;
  ref.read(homeBottomTerminalExpandedProvider.notifier).state = true;
  ref.read(navRailIndexStateProvider.notifier).state = 0;
  ref.read(showTerminalBadgeProvider.notifier).state = false;
}
