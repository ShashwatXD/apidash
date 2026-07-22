import 'package:flutter/material.dart';

enum WorkflowPortSide { left, right }

class WorkflowPort extends StatefulWidget {
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
  State<WorkflowPort> createState() => _WorkflowPortState();
}

class _WorkflowPortState extends State<WorkflowPort> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.highlighted || _hovered;
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      width: active ? 16 : 14,
      height: active ? 16 : 14,
      decoration: BoxDecoration(
        color: active ? widget.color : theme.colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.color,
          width: active ? 2.5 : 1.5,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
    );

    final labelWidget = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 120),
      style: theme.textTheme.labelSmall!.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: active ? widget.color : theme.colorScheme.onSurfaceVariant,
      ),
      child: Text(widget.label),
    );

    final children = widget.side == WorkflowPortSide.left
        ? [dot, const SizedBox(width: 4), labelWidget]
        : [labelWidget, const SizedBox(width: 4), dot];

    final content = MouseRegion(
      cursor: widget.onPointerDown != null
          ? SystemMouseCursors.grab
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );

    if (widget.onPointerDown != null) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: widget.onPointerDown,
        child: content,
      );
    }

    return content;
  }
}
