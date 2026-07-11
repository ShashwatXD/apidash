import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

enum WorkflowPortSide { left, right }

class WorkflowPort extends StatelessWidget {
  const WorkflowPort({
    super.key,
    required this.label,
    required this.side,
    required this.color,
    this.highlighted = false,
    this.onPointerDown,
  });

  final String label;
  final WorkflowPortSide side;
  final Color color;
  final bool highlighted;
  final void Function(PointerDownEvent event)? onPointerDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = highlighted;
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: active ? color : theme.colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: color,
          width: active ? 2.5 : 1.5,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
    );

    final labelWidget = Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: active ? color : theme.colorScheme.onSurfaceVariant,
      ),
    );

    final children = side == WorkflowPortSide.left
        ? [dot, const SizedBox(width: 4), labelWidget]
        : [labelWidget, const SizedBox(width: 4), dot];

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );

    if (onPointerDown != null) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: onPointerDown,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: content,
        ),
      );
    }

    return content;
  }
}
