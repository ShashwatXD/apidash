import 'package:apidash/consts.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/terminal/terminal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Collapsible integrated shell at the bottom of the request editor (desktop).
class HomeBottomTerminalBar extends ConsumerWidget {
  const HomeBottomTerminalBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsDesktop || kIsWeb) return const SizedBox.shrink();

    final expanded = ref.watch(homeBottomTerminalExpandedProvider);
    final override = ref.watch(shellTerminalCwdOverrideProvider);
    final ws = ref.watch(settingsProvider.select((s) => s.workspaceFolderPath));
    final shellCwd = (override != null && override.isNotEmpty)
        ? override
        : (ws != null && ws.isNotEmpty ? ws : null);

    final cs = Theme.of(context).colorScheme;

    return Material(
      elevation: expanded ? 2 : 0,
      color: cs.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              ref.read(homeBottomTerminalExpandedProvider.notifier).state =
                  !expanded;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    kLabelShell,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  Text(
                    expanded ? 'Hide' : 'Show',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: cs.primary),
                  ),
                ],
              ),
            ),
          ),
          if (override != null && override.isNotEmpty)
            Material(
              color: cs.surfaceContainerHighest,
              child: ListTile(
                dense: true,
                title: Text(
                  'Folder: $override',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: TextButton(
                  onPressed: () {
                    ref.read(shellTerminalCwdOverrideProvider.notifier).state =
                        null;
                  },
                  child: const Text('Reset'),
                ),
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: expanded
                ? SizedBox(
                    height: 280,
                    width: double.infinity,
                    child: ShellTerminalView(
                      key: ValueKey(shellCwd ?? 'default'),
                      workingDirectory: shellCwd,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
