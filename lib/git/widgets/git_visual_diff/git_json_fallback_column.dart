import 'package:apidash/widgets/widgets.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

import 'git_diff_snapshots.dart';
import 'git_request_visual_diff.dart';

class GitJsonFallbackColumn extends StatelessWidget {
  const GitJsonFallbackColumn({
    super.key,
    required this.raw,
    required this.fieldKey,
  });

  final String? raw;
  final String fieldKey;

  @override
  Widget build(BuildContext context) {
    if (raw == null || raw!.trim().isEmpty) {
      return const GitDiffEmptyState();
    }

    return Padding(
      padding: kP12,
      child: JsonTextFieldEditor(
        fieldKey: fieldKey,
        initialValue: prettyJson(raw),
        readOnly: true,
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
  }
}
