import 'package:flutter_riverpod/legacy.dart';

/// When set, [ShellTerminalView] uses this working directory.
final shellTerminalCwdOverrideProvider = StateProvider<String?>((ref) => null);

/// Whether the bottom [HomeBottomTerminalBar] shell panel is expanded.
final homeBottomTerminalExpandedProvider = StateProvider<bool>((ref) => false);
