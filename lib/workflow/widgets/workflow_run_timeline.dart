import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/providers/workflow_providers.dart';
import 'package:apidash/workflow/providers/workflow_ui_providers.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkflowRunTimeline extends ConsumerStatefulWidget {
  const WorkflowRunTimeline({super.key});

  @override
  ConsumerState<WorkflowRunTimeline> createState() =>
      _WorkflowRunTimelineState();
}

class _WorkflowRunTimelineState extends ConsumerState<WorkflowRunTimeline> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workflow = ref.watch(activeWorkflowProvider);
    final resultsById = ref.watch(workflowNodeRunResultsProvider);
    final stepOrder = ref.watch(workflowRunStepOrderProvider);
    final running = ref.watch(workflowRunInProgressProvider);

    if (workflow == null || (resultsById.isEmpty && !running)) {
      return const SizedBox.shrink();
    }

    final orderedResults = [
      for (final nodeId in stepOrder)
        if (resultsById[nodeId] case final result?) result,
    ];
    final failed = orderedResults
        .where((r) => r.status == WorkflowNodeRunStatus.failed)
        .length;
    final totalMs = orderedResults.fold<int>(
      0,
      (sum, result) => sum + (result.durationMs ?? 0),
    );

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.timeline_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  kHSpacer8,
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        running
                            ? 'Running workflow…'
                            : failed > 0
                            ? '${orderedResults.length} steps · $failed failed'
                            : '${orderedResults.length} steps completed',
                        key: ValueKey(
                          '$running-$failed-${orderedResults.length}',
                        ),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ),
                  if (!running && orderedResults.isNotEmpty)
                    Text(
                      '${totalMs}ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (running)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  kHSpacer4,
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1),
                      SizedBox(
                        height: 132,
                        child: orderedResults.isEmpty && running
                            ? Center(
                                child: Text(
                                  'Waiting for first step…',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: kPh8,
                                itemCount: orderedResults.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final result = orderedResults[index];
                                  final stepNumber = index + 1;
                                  final selected =
                                      ref.watch(
                                        selectedWorkflowNodeIdProvider,
                                      ) ==
                                      result.nodeId;
                                  return Material(
                                    color: selected
                                        ? theme.colorScheme.primaryContainer
                                              .withValues(alpha: 0.35)
                                        : null,
                                    borderRadius: BorderRadius.circular(8),
                                    child: ListTile(
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                      leading: CircleAvatar(
                                        radius: 12,
                                        backgroundColor: switch (result
                                            .status) {
                                          WorkflowNodeRunStatus.success =>
                                            Colors.green.withValues(
                                              alpha: 0.15,
                                            ),
                                          WorkflowNodeRunStatus.failed =>
                                            theme.colorScheme.errorContainer,
                                          WorkflowNodeRunStatus.running =>
                                            theme.colorScheme.primaryContainer,
                                          _ =>
                                            theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                        },
                                        child: Text(
                                          '$stepNumber',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Icon(
                                            switch (result.status) {
                                              WorkflowNodeRunStatus.success =>
                                                Icons.check_circle_outline,
                                              WorkflowNodeRunStatus.failed =>
                                                Icons.error_outline,
                                              WorkflowNodeRunStatus.running =>
                                                Icons.sync,
                                              _ => Icons.radio_button_unchecked,
                                            },
                                            size: 16,
                                            color: switch (result.status) {
                                              WorkflowNodeRunStatus.success =>
                                                Colors.green,
                                              WorkflowNodeRunStatus.failed =>
                                                theme.colorScheme.error,
                                              WorkflowNodeRunStatus.running =>
                                                theme.colorScheme.primary,
                                              _ => null,
                                            },
                                          ),
                                          kHSpacer6,
                                          Expanded(
                                            child: Text(
                                              [
                                                if (result.label.isEmpty)
                                                  result.nodeId
                                                else
                                                  result.label,
                                                if (result.loopIndex != null)
                                                  '#${int.tryParse(result.loopIndex!) != null ? (int.parse(result.loopIndex!) + 1) : result.loopIndex}',
                                              ].join(' '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        [
                                          if (result.statusCode != null)
                                            'HTTP ${result.statusCode}',
                                          if (result.durationMs != null)
                                            '${result.durationMs} ms',
                                          if (result.message != null &&
                                              result.message!.isNotEmpty)
                                            result.message,
                                        ].join(' · '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall,
                                      ),
                                      onTap: () {
                                        ref
                                                .read(
                                                  selectedWorkflowNodeIdProvider
                                                      .notifier,
                                                )
                                                .state =
                                            result.nodeId;
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
