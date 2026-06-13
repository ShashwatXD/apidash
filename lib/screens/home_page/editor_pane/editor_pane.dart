import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/consts.dart';
import 'package:apidash/git/widgets/git_status_badge.dart';
import 'editor_default.dart';
import 'editor_request.dart';

class RequestEditorPane extends ConsumerWidget {
  const RequestEditorPane({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedIdStateProvider);
    if (selectedId == null) {
      return Padding(
        padding: kIsMacOS ? kPt28o8 : kP8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kIsDesktop)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [GitStatusBadge()],
              ),
            const Expanded(child: RequestEditorDefault()),
          ],
        ),
      );
    } else {
      return const RequestEditor();
    }
  }
}
