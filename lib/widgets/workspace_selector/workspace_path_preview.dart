import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

class WorkspacePathPreview extends StatelessWidget {
  const WorkspacePathPreview({
    super.key,
    required this.label,
    required this.path,
  });

  final String label;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayPath = path?.trim();

    if (displayPath == null || displayPath.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: kCodeStyle.copyWith(
            fontSize: 12,
            color: scheme.outline,
          ),
        ),
        kVSpacer5,
        SelectableText(
          displayPath,
          style: kCodeStyle.copyWith(
            fontSize: 12,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}
