import 'package:apidash/consts.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/widgets/workflow_canvas_constants.dart';
import 'package:apidash/workflow/widgets/workflow_port.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class WorkflowRequestNodeCard extends StatelessWidget {
  const WorkflowRequestNodeCard({
    super.key,
    required this.node,
    required this.step,
    required this.selected,
    required this.runResult,
    this.highlightInput = false,
    this.highlightSuccess = false,
    this.highlightFailure = false,
    this.onTap,
    this.onDoubleTap,
    this.onDuplicate,
    this.onDelete,
    this.onDragPanUpdate,
    this.onDragPanEnd,
    this.onWirePointerDown,
  });

  final WorkflowGraphNode node;
  final WorkflowStep? step;
  final bool selected;
  final WorkflowNodeRunResult? runResult;
  final bool highlightInput;
  final bool highlightSuccess;
  final bool highlightFailure;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final GestureDragUpdateCallback? onDragPanUpdate;
  final GestureDragEndCallback? onDragPanEnd;
  final void Function(PointerDownEvent event, WorkflowEdgeHandle handle)?
      onWirePointerDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = step?.request ?? const <String, dynamic>{};
    final http = request['httpRequestModel'];
    final method = http is Map
        ? (http['method'] as String? ?? HTTPVerb.get.name).toUpperCase()
        : 'GET';
    final url = http is Map ? (http['url'] as String? ?? '') : '';
    final borderColor = switch (runResult?.status) {
      WorkflowNodeRunStatus.running => theme.colorScheme.primary,
      WorkflowNodeRunStatus.success => Colors.green,
      WorkflowNodeRunStatus.failed => theme.colorScheme.error,
      _ => selected ? theme.colorScheme.primary : theme.dividerColor,
    };

    return SizedBox(
      width: kWorkflowRequestNodeWidth,
      height: kWorkflowRequestNodeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              onPanUpdate: onDragPanUpdate,
              onPanEnd: onDragPanEnd,
              child: Material(
                elevation: selected ? 2 : 0,
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.http,
                              size: 20,
                              color: theme.colorScheme.onSurface,
                            ),
                            kHSpacer8,
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                method,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            kHSpacer8,
                            Expanded(
                              child: Text(
                                node.label.isNotEmpty ? node.label : 'HTTP Request',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            if (selected) ...[
                              _NodeActionButton(
                                icon: Icons.copy_outlined,
                                tooltip: kTooltipDuplicate,
                                onPressed: onDuplicate,
                              ),
                              _NodeActionButton(
                                icon: Icons.delete_outline,
                                tooltip: kTooltipDelete,
                                onPressed: onDelete,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(
                                alpha: 0.45,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.outline.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            child: Text(
                              url.isEmpty ? 'No URL configured' : url,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                        if (node.extractions.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          ...node.extractions.map(
                            (extraction) => Text(
                              '→ {{${extraction.varName}}} from ${extraction.jsonPath}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ],
                        if (runResult?.durationMs != null)
                          Text(
                            '${runResult!.durationMs} ms',
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ),
          Positioned(
            left: -6,
            top: kRequestPortSendY - 10,
            child: WorkflowPort(
              label: 'Send',
              side: WorkflowPortSide.left,
              color: theme.colorScheme.primary,
              highlighted: highlightInput,
            ),
          ),
          Positioned(
            right: -6,
            top: kRequestPortSuccessY - 10,
            child: WorkflowPort(
              label: 'Success()',
              side: WorkflowPortSide.right,
              color: Colors.green,
              highlighted: highlightSuccess,
              onPointerDown: (event) => onWirePointerDown?.call(
                event,
                WorkflowEdgeHandle.success,
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: kRequestPortFailY - 10,
            child: WorkflowPort(
              label: 'Fail()',
              side: WorkflowPortSide.right,
              color: theme.colorScheme.error,
              highlighted: highlightFailure,
              onPointerDown: (event) => onWirePointerDown?.call(
                event,
                WorkflowEdgeHandle.failure,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeActionButton extends StatelessWidget {
  const _NodeActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      icon: Icon(icon, size: 16),
    );
  }
}

class WorkflowStartNodeCard extends StatelessWidget {
  const WorkflowStartNodeCard({
    super.key,
    required this.node,
    required this.selected,
    this.highlightNext = false,
    this.onTap,
    this.onDragPanUpdate,
    this.onDragPanEnd,
    this.onWirePointerDown,
  });

  final WorkflowGraphNode node;
  final bool selected;
  final bool highlightNext;
  final VoidCallback? onTap;
  final GestureDragUpdateCallback? onDragPanUpdate;
  final GestureDragEndCallback? onDragPanEnd;
  final void Function(PointerDownEvent event, WorkflowEdgeHandle handle)?
      onWirePointerDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: kWorkflowStartNodeWidth,
      height: kWorkflowStartNodeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: onDragPanUpdate,
              onPanEnd: onDragPanEnd,
              child: Material(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.dividerColor,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_outline, size: 22),
                        kHSpacer8,
                        Expanded(
                          child: Text(
                            node.label.isEmpty ? 'Start' : node.label,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: kStartPortNextY - 10,
            child: WorkflowPort(
              label: 'Next',
              side: WorkflowPortSide.right,
              color: theme.colorScheme.primary,
              highlighted: highlightNext,
              onPointerDown: (event) => onWirePointerDown?.call(
                event,
                WorkflowEdgeHandle.next,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkflowConditionNodeCard extends StatelessWidget {
  const WorkflowConditionNodeCard({
    super.key,
    required this.node,
    required this.selected,
    this.highlightInput = false,
    this.highlightThen = false,
    this.highlightElse = false,
    this.onTap,
    this.onDragPanUpdate,
    this.onDragPanEnd,
    this.onWirePointerDown,
  });

  final WorkflowGraphNode node;
  final bool selected;
  final bool highlightInput;
  final bool highlightThen;
  final bool highlightElse;
  final VoidCallback? onTap;
  final GestureDragUpdateCallback? onDragPanUpdate;
  final GestureDragEndCallback? onDragPanEnd;
  final void Function(PointerDownEvent event, WorkflowEdgeHandle handle)?
      onWirePointerDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: kWorkflowConditionNodeWidth,
      height: kWorkflowConditionNodeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: onDragPanUpdate,
              onPanEnd: onDragPanEnd,
              child: Material(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.dividerColor,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.rule, size: 20),
                            kHSpacer8,
                            Expanded(
                              child: Text(
                                node.label.isEmpty ? 'Condition' : node.label,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          node.conditionExpression ?? 'true',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -6,
            top: kWorkflowConditionNodeHeight / 2 - 10,
            child: WorkflowPort(
              label: 'In',
              side: WorkflowPortSide.left,
              color: theme.colorScheme.primary,
              highlighted: highlightInput,
            ),
          ),
          Positioned(
            right: -6,
            top: kConditionPortThenY - 10,
            child: WorkflowPort(
              label: 'True',
              side: WorkflowPortSide.right,
              color: Colors.green,
              highlighted: highlightThen,
              onPointerDown: (event) => onWirePointerDown?.call(
                event,
                WorkflowEdgeHandle.then,
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: kConditionPortElseY - 10,
            child: WorkflowPort(
              label: 'False',
              side: WorkflowPortSide.right,
              color: theme.colorScheme.error,
              highlighted: highlightElse,
              onPointerDown: (event) => onWirePointerDown?.call(
                event,
                WorkflowEdgeHandle.elseBranch,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
