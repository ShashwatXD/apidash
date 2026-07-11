import 'package:apidash/models/models.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:apidash/workflow/engine/extraction_service.dart';
import 'package:apidash/workflow/engine/workflow_request_executor.dart';
import 'package:apidash/workflow/engine/workflow_validator.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

RequestModel resolveWorkflowStepRequest({
  required WorkflowStep step,
  required WorkspaceStorage storage,
}) {
  var payload = Map<String, dynamic>.from(step.request);
  final inheritFrom = step.inheritFrom;
  if (inheritFrom != null) {
    final inherited = storage.getRequestModel(
      inheritFrom.collectionId,
      inheritFrom.requestId,
    );
    if (inherited != null) {
      payload = {
        ...inherited,
        ...payload,
      };
    }
  }
  return RequestModel.fromJson(Map<String, Object?>.from(payload));
}

class WorkflowRunner {
  const WorkflowRunner({
    this.validator = const WorkflowValidator(),
    this.extractionService = const WorkflowExtractionService(),
  });

  final WorkflowValidator validator;
  final WorkflowExtractionService extractionService;

  Future<WorkflowRunResult> run({
    required WidgetRef ref,
    required WorkflowDocument workflow,
    required WorkspaceStorage storage,
    void Function(WorkflowNodeRunResult result)? onNodeUpdate,
    bool Function()? shouldStop,
  }) async {
    final startedAt = DateTime.now();
    final validation = validator.validate(workflow);
    if (!validation.isValid) {
      return WorkflowRunResult(
        workflowId: workflow.id,
        success: false,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        nodeResults: const [],
        error: validation.errors.first,
      );
    }

    final scopedVariables = <String, String>{
      for (final variable in workflow.flowVariables)
        if (variable.enabled && variable.key.isNotEmpty)
          variable.key: variable.value,
    };
    final nodeResults = <WorkflowNodeRunResult>[];
    final queue = List<WorkflowGraphNode>.from(validator.entryNodes(workflow));
    final adjacency = _buildAdjacency(workflow);
    final visited = <String>{};
    int? lastStatusCode;

    while (queue.isNotEmpty) {
      if (shouldStop?.call() ?? false) {
        return WorkflowRunResult(
          workflowId: workflow.id,
          success: false,
          startedAt: startedAt,
          endedAt: DateTime.now(),
          nodeResults: nodeResults,
          error: 'Workflow stopped',
          scopedVariables: scopedVariables,
        );
      }

      final node = queue.removeAt(0);
      if (!visited.add(node.id)) {
        continue;
      }
      final nodeStartedAt = DateTime.now();
      var running = WorkflowNodeRunResult(
        nodeId: node.id,
        label: node.label,
        status: WorkflowNodeRunStatus.running,
      );
      onNodeUpdate?.call(running);

      WorkflowNodeRunResult result;
      var branchHandle = WorkflowEdgeHandle.success;

      switch (node.type) {
        case WorkflowNodeType.manualStart:
          result = WorkflowNodeRunResult(
            nodeId: node.id,
            label: node.label,
            status: WorkflowNodeRunStatus.success,
            durationMs: 0,
          );
          branchHandle = WorkflowEdgeHandle.next;
        case WorkflowNodeType.condition:
          final passed = _evaluateCondition(
            node.conditionExpression,
            scopedVariables: scopedVariables,
            lastStatusCode: lastStatusCode,
          );
          result = WorkflowNodeRunResult(
            nodeId: node.id,
            label: node.label,
            status: WorkflowNodeRunStatus.success,
            message: passed ? 'Condition true' : 'Condition false',
            durationMs: DateTime.now().difference(nodeStartedAt).inMilliseconds,
          );
          branchHandle =
              passed ? WorkflowEdgeHandle.then : WorkflowEdgeHandle.elseBranch;
        case WorkflowNodeType.request:
          final stepKey = node.stepKey;
          final step = stepKey == null ? null : workflow.steps[stepKey];
          if (step == null) {
            result = WorkflowNodeRunResult(
              nodeId: node.id,
              label: node.label,
              status: WorkflowNodeRunStatus.failed,
              message: 'Missing workflow step',
            );
            branchHandle = WorkflowEdgeHandle.failure;
            nodeResults.add(result);
            onNodeUpdate?.call(result);
            return WorkflowRunResult(
              workflowId: workflow.id,
              success: false,
              startedAt: startedAt,
              endedAt: DateTime.now(),
              nodeResults: nodeResults,
              error: 'Missing workflow step',
              scopedVariables: scopedVariables,
            );
          }
          final requestModel = resolveWorkflowStepRequest(
            step: step,
            storage: storage,
          );
          final execution = await executeWorkflowRequest(
            ref: ref,
            requestModel: requestModel,
            scopedVariables: scopedVariables,
            logLabel: '${workflow.id}/${stepKey ?? node.id}',
          );
          lastStatusCode = execution.statusCode;
          for (final extraction in node.extractions) {
            final value = extractionService.extract(
              source: extraction.source,
              jsonPath: extraction.jsonPath,
              response: execution.httpResponseModel,
              statusCode: execution.statusCode,
            );
            if (value != null && extraction.varName.isNotEmpty) {
              scopedVariables[extraction.varName] = value;
            }
          }
          final ok = execution.ok;
          result = WorkflowNodeRunResult(
            nodeId: node.id,
            label: node.label,
            status: ok
                ? WorkflowNodeRunStatus.success
                : WorkflowNodeRunStatus.failed,
            message: execution.message,
            statusCode: execution.statusCode,
            durationMs: execution.duration?.inMilliseconds ??
                DateTime.now().difference(nodeStartedAt).inMilliseconds,
          );
          branchHandle =
              ok ? WorkflowEdgeHandle.success : WorkflowEdgeHandle.failure;
          if (!ok && node.onFailure == 'abort') {
            nodeResults.add(result);
            onNodeUpdate?.call(result);
            return WorkflowRunResult(
              workflowId: workflow.id,
              success: false,
              startedAt: startedAt,
              endedAt: DateTime.now(),
              nodeResults: nodeResults,
              error: execution.message ?? 'Request step failed',
              scopedVariables: scopedVariables,
            );
          }
      }

      nodeResults.add(result);
      onNodeUpdate?.call(result);

      final nextIds = (adjacency[node.id] ?? const <_WorkflowEdgeRef>[])
          .where((edge) => edge.sourceHandle == branchHandle)
          .map((edge) => edge.targetId)
          .toList();
      if (nextIds.isEmpty && node.type == WorkflowNodeType.request) {
        final fallback = (adjacency[node.id] ?? const <_WorkflowEdgeRef>[])
            .where(
              (edge) =>
                  edge.sourceHandle != WorkflowEdgeHandle.then &&
                  edge.sourceHandle != WorkflowEdgeHandle.elseBranch &&
                  edge.sourceHandle != WorkflowEdgeHandle.success &&
                  edge.sourceHandle != WorkflowEdgeHandle.failure,
            )
            .map((edge) => edge.targetId);
        nextIds.addAll(fallback);
      }

      for (final nextId in nextIds) {
        final nextNode = workflow.graph.nodes
            .where((candidate) => candidate.id == nextId)
            .cast<WorkflowGraphNode?>()
            .firstWhere((candidate) => candidate != null, orElse: () => null);
        if (nextNode != null) {
          queue.add(nextNode);
        }
      }
    }

    final failed = nodeResults.any(
      (result) => result.status == WorkflowNodeRunStatus.failed,
    );
    return WorkflowRunResult(
      workflowId: workflow.id,
      success: !failed,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      nodeResults: nodeResults,
      scopedVariables: scopedVariables,
      error: failed ? 'One or more steps failed' : null,
    );
  }

  bool _evaluateCondition(
    String? expression, {
    required Map<String, String> scopedVariables,
    required int? lastStatusCode,
  }) {
    final exp = expression?.trim().toLowerCase();
    if (exp == null || exp.isEmpty || exp == 'true') {
      return true;
    }
    if (exp == 'false') {
      return false;
    }
    if (exp.startsWith('var:')) {
      final key = exp.substring(4).trim();
      final value = scopedVariables[key];
      return value != null && value.isNotEmpty;
    }
    if (lastStatusCode == null) {
      return false;
    }
    if (exp == 'status>=200') {
      return lastStatusCode >= 200;
    }
    if (exp == 'status<400') {
      return lastStatusCode < 400;
    }
    if (exp == 'status>=200&&status<300') {
      return lastStatusCode >= 200 && lastStatusCode < 300;
    }
    return false;
  }

  Map<String, List<_WorkflowEdgeRef>> _buildAdjacency(WorkflowDocument workflow) {
    final map = <String, List<_WorkflowEdgeRef>>{};
    for (final edge in workflow.graph.edges) {
      map.putIfAbsent(edge.source, () => []).add(
            _WorkflowEdgeRef(
              targetId: edge.target,
              sourceHandle: edge.sourceHandle,
            ),
          );
    }
    return map;
  }
}

class _WorkflowEdgeRef {
  const _WorkflowEdgeRef({
    required this.targetId,
    required this.sourceHandle,
  });

  final String targetId;
  final WorkflowEdgeHandle sourceHandle;
}
