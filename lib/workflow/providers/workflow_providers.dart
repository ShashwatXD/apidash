import 'package:apidash/consts.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/providers/settings_providers.dart';
import 'package:apidash/services/storage/workspace_storage.dart';
import 'package:apidash/utils/utils.dart';
import 'package:apidash/workflow/engine/workflow_auto_arrange.dart';
import 'package:apidash/workflow/engine/workflow_runner.dart';
import 'package:apidash/workflow/engine/workflow_templates.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/providers/workflow_ui_providers.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final selectedWorkflowIdStateProvider = StateProvider<String?>((ref) => null);

final workflowSearchQueryProvider = StateProvider<String>((ref) => '');

final workflowRunInProgressProvider = StateProvider<bool>((ref) => false);

final workflowNodeRunResultsProvider =
    StateProvider<Map<String, WorkflowNodeRunResult>>((ref) => {});

final workflowRunStepOrderProvider = StateProvider<List<String>>((ref) => []);

final workflowCatalogProvider =
    AsyncNotifierProvider<WorkflowCatalogNotifier, List<WorkflowSummary>>(
  WorkflowCatalogNotifier.new,
);

final activeWorkflowProvider =
    NotifierProvider<ActiveWorkflowNotifier, WorkflowDocument?>(
  ActiveWorkflowNotifier.new,
);

class WorkflowSummary {
  const WorkflowSummary({
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.stepCount,
  });

  final String id;
  final String name;
  final DateTime modifiedAt;
  final int stepCount;
}

class WorkflowCatalogNotifier extends AsyncNotifier<List<WorkflowSummary>> {
  @override
  Future<List<WorkflowSummary>> build() async {
    if (!isWorkspaceStorageInitialized()) {
      return const [];
    }
    return _loadSummaries();
  }

  List<WorkflowSummary> _loadSummaries() {
    final summaries = <WorkflowSummary>[
      for (final name in workspaceStorage.getKnownWorkflowIds())
        _summaryFor(name),
    ];
    summaries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return summaries;
  }

  WorkflowSummary _summaryFor(String name) {
    final json = workspaceStorage.getWorkflow(name);
    if (json == null) {
      return WorkflowSummary(
        id: name,
        name: name,
        modifiedAt: DateTime.now(),
        stepCount: 0,
      );
    }
    final workflow = WorkflowDocument.fromJson(json);
    final workflowName = workflow.name.trim().isNotEmpty ? workflow.name : name;
    return WorkflowSummary(
      id: workflowName,
      name: workflowName,
      modifiedAt: workflow.modifiedAt,
      stepCount: workflow.steps.length,
    );
  }

  Future<void> reloadFromDisk() async {
    state = AsyncData(_loadSummaries());
  }

  Future<WorkflowDocument> createWorkflow({
    String? name,
    WorkflowTemplate? template,
  }) async {
    final now = DateTime.now();
    final baseName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : template != null
            ? WorkflowTemplates.templates
                .firstWhere((info) => info.template == template)
                .title
            : 'Workflow ${(state.value?.length ?? 0) + 1}';
    final workflowName = _uniqueWorkflowName(baseName);
    final workflow = template != null
        ? WorkflowTemplates.build(
            template: template,
            name: workflowName,
            now: now,
          )
        : _defaultWorkflow(name: workflowName, now: now);
    await _persistWorkflow(workflow);
    await reloadFromDisk();
    ref.read(selectedWorkflowIdStateProvider.notifier).state = workflowName;
    ref.read(activeWorkflowProvider.notifier).load(workflowName);
    return workflow;
  }

  Future<void> deleteWorkflow(String workflowName) async {
    await workspaceStorage.deleteWorkflow(workflowName);
    final remaining = workspaceStorage
        .getWorkflowsIndex()
        .where((name) => name != workflowName)
        .toList();
    await workspaceStorage.setWorkflowsIndex(remaining);
    await reloadFromDisk();
    if (ref.read(selectedWorkflowIdStateProvider) == workflowName) {
      ref.read(selectedWorkflowIdStateProvider.notifier).state =
          remaining.isNotEmpty ? remaining.first : null;
      if (remaining.isNotEmpty) {
        await ref.read(activeWorkflowProvider.notifier).load(remaining.first);
      } else {
        ref.read(activeWorkflowProvider.notifier).clear();
      }
    }
  }

  Future<void> renameWorkflow(String workflowName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == workflowName) {
      return;
    }
    final uniqueName = _uniqueWorkflowName(trimmed, except: workflowName);
    await workspaceStorage.renameWorkflow(workflowName, uniqueName);
    if (ref.read(selectedWorkflowIdStateProvider) == workflowName) {
      ref.read(selectedWorkflowIdStateProvider.notifier).state = uniqueName;
    }
    await ref.read(activeWorkflowProvider.notifier).load(uniqueName);
    await reloadFromDisk();
  }

  String _uniqueWorkflowName(String baseName, {String? except}) {
    final existing = workspaceStorage.getWorkflowsIndex().toSet();
    if (except != null) {
      existing.remove(except);
    }
    if (!existing.contains(baseName)) {
      return baseName;
    }
    var suffix = 2;
    while (existing.contains('$baseName ($suffix)')) {
      suffix += 1;
    }
    return '$baseName ($suffix)';
  }

  Future<void> _persistWorkflow(WorkflowDocument workflow) async {
    await workspaceStorage.setWorkflow(workflow.id, workflow.toJson());
    final index = workspaceStorage.getWorkflowsIndex().toList();
    if (!index.contains(workflow.id)) {
      index.add(workflow.id);
    }
    await workspaceStorage.setWorkflowsIndex(index);
  }
}

class ActiveWorkflowNotifier extends Notifier<WorkflowDocument?> {
  @override
  WorkflowDocument? build() => null;

  Future<void> load(String workflowId) async {
    final json = workspaceStorage.getWorkflow(workflowId);
    if (json == null) {
      state = null;
      return;
    }
    state = WorkflowDocument.fromJson(json);
  }

  void clear() => state = null;

  Future<void> save(WorkflowDocument workflow) async {
    final name = workflow.name.trim().isNotEmpty ? workflow.name.trim() : workflow.id;
    final updated = workflow.copyWith(
      id: name,
      name: name,
      modifiedAt: DateTime.now(),
    );
    state = updated;
    await workspaceStorage.setWorkflow(updated.id, updated.toJson());
    final index = workspaceStorage.getWorkflowsIndex().toList();
    if (!index.contains(updated.id)) {
      index.add(updated.id);
    }
    await workspaceStorage.setWorkflowsIndex(index);
    await ref.read(workflowCatalogProvider.notifier).reloadFromDisk();
  }

  Future<void> updateWorkflow(
    WorkflowDocument Function(WorkflowDocument current) transform,
  ) async {
    final current = state;
    if (current == null) {
      return;
    }
    await save(transform(current));
  }

  Future<String?> addRequestStep({
    Offset position = const Offset(280, 180),
    String? afterNodeId,
    APIType apiType = APIType.rest,
  }) async {
    final current = state;
    if (current == null) {
      return null;
    }
    final stepKey = 'step_${getNewUuid().substring(0, 8)}';
    final requestId = getNewUuid();
    final label = apiType == APIType.ai
        ? 'AI Request ${current.steps.length + 1}'
        : 'Request ${current.steps.length + 1}';
    final RequestModel requestModel;
    if (apiType == APIType.ai) {
      final defaultModel = ref.read(settingsProvider).defaultAIModel;
      requestModel = RequestModel(
        id: requestId,
        name: label,
        apiType: APIType.ai,
        aiRequestModel: defaultModel == null
            ? const AIRequestModel()
            : AIRequestModel.fromJson(defaultModel),
      );
    } else {
      requestModel = RequestModel(
        id: requestId,
        name: label,
        apiType: APIType.rest,
        httpRequestModel: const HttpRequestModel(
          method: HTTPVerb.get,
          url: 'https://',
        ),
      );
    }
    final step = WorkflowStep(
      label: label,
      request: requestModel.toJson(),
    );
    final nodeId = 'node_${getNewUuid().substring(0, 8)}';
    final nodes = [...current.graph.nodes];
    final edges = [...current.graph.edges];
    final newNode = WorkflowGraphNode(
      id: nodeId,
      type: WorkflowNodeType.request,
      stepKey: stepKey,
      label: label,
      position: WorkflowPosition(x: position.dx, y: position.dy),
    );
    nodes.add(newNode);
    if (afterNodeId != null) {
      edges.add(
        WorkflowGraphEdge(
          id: 'edge_${getNewUuid().substring(0, 8)}',
          source: afterNodeId,
          sourceHandle: _sourceHandleForNode(current, afterNodeId),
          target: nodeId,
        ),
      );
    }
    await save(
      current.copyWith(
        steps: {...current.steps, stepKey: step},
        graph: current.graph.copyWith(nodes: nodes, edges: edges),
      ),
    );
    ref.read(selectedWorkflowNodeIdProvider.notifier).state = nodeId;
    return nodeId;
  }

  Future<String?> addLoopNode({
    Offset position = const Offset(320, 240),
    String? afterNodeId,
  }) async {
    final current = state;
    if (current == null) {
      return null;
    }
    final nodeId = 'node_${getNewUuid().substring(0, 8)}';
    const label = 'For each';
    final nodes = [...current.graph.nodes];
    final edges = [...current.graph.edges];
    nodes.add(
      WorkflowGraphNode(
        id: nodeId,
        type: WorkflowNodeType.loop,
        label: label,
        position: WorkflowPosition(x: position.dx, y: position.dy),
        loopExpression: 'var:items',
      ),
    );
    if (afterNodeId != null) {
      edges.add(
        WorkflowGraphEdge(
          id: 'edge_${getNewUuid().substring(0, 8)}',
          source: afterNodeId,
          sourceHandle: _sourceHandleForNode(current, afterNodeId),
          target: nodeId,
        ),
      );
    }
    await save(
      current.copyWith(
        graph: current.graph.copyWith(nodes: nodes, edges: edges),
      ),
    );
    ref.read(selectedWorkflowNodeIdProvider.notifier).state = nodeId;
    return nodeId;
  }

  Future<String?> addConditionNode({
    Offset position = const Offset(320, 240),
    String? afterNodeId,
  }) async {
    final current = state;
    if (current == null) {
      return null;
    }
    final nodeId = 'node_${getNewUuid().substring(0, 8)}';
    const label = 'Condition';
    final nodes = [...current.graph.nodes];
    final edges = [...current.graph.edges];
    nodes.add(
      WorkflowGraphNode(
        id: nodeId,
        type: WorkflowNodeType.condition,
        label: label,
        position: WorkflowPosition(x: position.dx, y: position.dy),
        conditionExpression: 'status>=200',
      ),
    );
    if (afterNodeId != null) {
      edges.add(
        WorkflowGraphEdge(
          id: 'edge_${getNewUuid().substring(0, 8)}',
          source: afterNodeId,
          sourceHandle: _sourceHandleForNode(current, afterNodeId),
          target: nodeId,
        ),
      );
    }
    await save(
      current.copyWith(
        graph: current.graph.copyWith(nodes: nodes, edges: edges),
      ),
    );
    ref.read(selectedWorkflowNodeIdProvider.notifier).state = nodeId;
    return nodeId;
  }

  Future<String?> duplicateRequestStep(String nodeId) async {
    final current = state;
    if (current == null) {
      return null;
    }
    final node = current.graph.nodes
        .where((candidate) => candidate.id == nodeId)
        .cast<WorkflowGraphNode?>()
        .firstWhere((candidate) => candidate != null, orElse: () => null);
    if (node == null || node.stepKey == null) {
      return null;
    }
    final sourceStep = current.steps[node.stepKey];
    if (sourceStep == null) {
      return null;
    }

    final stepKey = 'step_${getNewUuid().substring(0, 8)}';
    final newNodeId = 'node_${getNewUuid().substring(0, 8)}';
    final requestId = getNewUuid();
    final baseLabel = node.label.isNotEmpty ? node.label : sourceStep.label;
    final copyLabel = '$baseLabel copy';
    final sourceRequest = RequestModel.fromJson(
      Map<String, Object?>.from(sourceStep.request),
    );
    final step = WorkflowStep(
      label: copyLabel,
      request: sourceRequest
          .copyWith(
            id: requestId,
            name: copyLabel,
            httpResponseModel: null,
            responseStatus: null,
            message: null,
            isWorking: false,
            isStreaming: false,
          )
          .toJson(),
      inheritFrom: sourceStep.inheritFrom,
    );
    final newNode = WorkflowGraphNode(
      id: newNodeId,
      type: WorkflowNodeType.request,
      stepKey: stepKey,
      label: copyLabel,
      position: WorkflowPosition(
        x: node.position.x + 36,
        y: node.position.y + 36,
      ),
      extractions: [...node.extractions],
    );

    await save(
      current.copyWith(
        steps: {...current.steps, stepKey: step},
        graph: current.graph.copyWith(
          nodes: [...current.graph.nodes, newNode],
        ),
      ),
    );
    return newNodeId;
  }

  Future<String?> duplicateNode(String nodeId) async {
    final current = state;
    if (current == null) {
      return null;
    }
    final node = current.graph.nodes
        .where((candidate) => candidate.id == nodeId)
        .cast<WorkflowGraphNode?>()
        .firstWhere((candidate) => candidate != null, orElse: () => null);
    if (node == null || node.type == WorkflowNodeType.manualStart) {
      return null;
    }
    if (node.type == WorkflowNodeType.request) {
      return duplicateRequestStep(nodeId);
    }

    final newNodeId = 'node_${getNewUuid().substring(0, 8)}';
    final baseLabel = node.label.isNotEmpty
        ? node.label
        : switch (node.type) {
            WorkflowNodeType.loop => kLabelWorkflowLoop,
            WorkflowNodeType.condition => kLabelWorkflowCondition,
            _ => 'Node',
          };
    final newNode = node.copyWith(
      id: newNodeId,
      label: '$baseLabel copy',
      position: WorkflowPosition(
        x: node.position.x + 36,
        y: node.position.y + 36,
      ),
    );

    await save(
      current.copyWith(
        graph: current.graph.copyWith(
          nodes: [...current.graph.nodes, newNode],
        ),
      ),
    );
    ref.read(selectedWorkflowNodeIdProvider.notifier).state = newNodeId;
    return newNodeId;
  }

  Future<String?> importRequestFromCollection({
    required String collectionId,
    required String requestId,
    Offset position = const Offset(280, 180),
    String? afterNodeId,
  }) async {
    final json = workspaceStorage.getRequestModel(collectionId, requestId);
    if (json == null) {
      return null;
    }
    final request = RequestModel.fromJson(Map<String, Object?>.from(json));
    final current = state;
    if (current == null) {
      return null;
    }
    final stepKey = 'step_${getNewUuid().substring(0, 8)}';
    final nodeId = 'node_${getNewUuid().substring(0, 8)}';
    final label = request.name.isNotEmpty ? request.name : 'Imported request';
    final step = WorkflowStep(
      label: label,
      request: request
          .copyWith(
            id: getNewUuid(),
            httpResponseModel: null,
            responseStatus: null,
            message: null,
            isWorking: false,
            isStreaming: false,
          )
          .toJson(),
      inheritFrom: WorkflowInheritFrom(
        collectionId: collectionId,
        requestId: requestId,
      ),
    );
    final nodes = [...current.graph.nodes];
    final edges = [...current.graph.edges];
    nodes.add(
      WorkflowGraphNode(
        id: nodeId,
        type: WorkflowNodeType.request,
        stepKey: stepKey,
        label: label,
        position: WorkflowPosition(x: position.dx, y: position.dy),
      ),
    );
    if (afterNodeId != null) {
      edges.add(
        WorkflowGraphEdge(
          id: 'edge_${getNewUuid().substring(0, 8)}',
          source: afterNodeId,
          sourceHandle: _sourceHandleForNode(current, afterNodeId),
          target: nodeId,
        ),
      );
    }
    await save(
      current.copyWith(
        steps: {...current.steps, stepKey: step},
        graph: current.graph.copyWith(nodes: nodes, edges: edges),
      ),
    );
    ref.read(selectedWorkflowNodeIdProvider.notifier).state = nodeId;
    return nodeId;
  }

  Future<void> updateNodePosition(String nodeId, Offset position) async {
    final current = state;
    if (current == null) {
      return;
    }
    final nodes = [
      for (final node in current.graph.nodes)
        if (node.id == nodeId)
          node.copyWith(
            position: WorkflowPosition(x: position.dx, y: position.dy),
          )
        else
          node,
    ];
    await save(current.copyWith(graph: current.graph.copyWith(nodes: nodes)));
  }

  Future<void> autoArrangeGraph() async {
    final current = state;
    if (current == null) {
      return;
    }
    final positions = computeWorkflowAutoArrangePositions(current.graph);
    if (positions.isEmpty) {
      return;
    }
    final nodes = [
      for (final node in current.graph.nodes)
        if (positions.containsKey(node.id))
          node.copyWith(
            position: WorkflowPosition(
              x: positions[node.id]!.dx,
              y: positions[node.id]!.dy,
            ),
          )
        else
          node,
    ];
    await save(current.copyWith(graph: current.graph.copyWith(nodes: nodes)));
  }

  Future<void> updateSelectedNode(WorkflowGraphNode node) async {
    final current = state;
    if (current == null) {
      return;
    }
    final nodes = [
      for (final existing in current.graph.nodes)
        if (existing.id == node.id) node else existing,
    ];
    var steps = current.steps;
    final stepKey = node.stepKey;
    if (node.type == WorkflowNodeType.request &&
        stepKey != null &&
        steps.containsKey(stepKey)) {
      steps = {
        ...steps,
        stepKey: steps[stepKey]!.copyWith(label: node.label),
      };
    }
    await save(
      current.copyWith(
        steps: steps,
        graph: current.graph.copyWith(nodes: nodes),
      ),
    );
  }

  Future<void> updateStepRequest(String stepKey, RequestModel request) async {
    final current = state;
    if (current == null || !current.steps.containsKey(stepKey)) {
      return;
    }
    final step = current.steps[stepKey]!;
    await save(
      current.copyWith(
        steps: {
          ...current.steps,
          stepKey: step.copyWith(
            label: request.name.isNotEmpty ? request.name : step.label,
            request: request
                .copyWith(
                  httpResponseModel: null,
                  responseStatus: null,
                  message: null,
                  isWorking: false,
                  isStreaming: false,
                )
                .toJson(),
          ),
        },
      ),
    );
  }

  Future<void> connectNodes({
    required String sourceId,
    required WorkflowEdgeHandle sourceHandle,
    required String targetId,
  }) async {
    final current = state;
    if (current == null) {
      return;
    }
    final edge = WorkflowGraphEdge(
      id: 'edge_${getNewUuid().substring(0, 8)}',
      source: sourceId,
      sourceHandle: sourceHandle,
      target: targetId,
    );
    await save(
      current.copyWith(
        graph: current.graph.copyWith(
          edges: [...current.graph.edges, edge],
        ),
      ),
    );
  }

  Future<void> disconnectEdge(String edgeId) async {
    final current = state;
    if (current == null) {
      return;
    }
    await save(
      current.copyWith(
        graph: current.graph.copyWith(
          edges: current.graph.edges.where((edge) => edge.id != edgeId).toList(),
        ),
      ),
    );
  }

  Future<void> deleteNode(String nodeId) async {
    final current = state;
    if (current == null) {
      return;
    }
    final node = current.graph.nodes
        .where((candidate) => candidate.id == nodeId)
        .cast<WorkflowGraphNode?>()
        .firstWhere((candidate) => candidate != null, orElse: () => null);
    if (node == null) {
      return;
    }
    final steps = Map<String, WorkflowStep>.from(current.steps);
    if (node.stepKey != null) {
      steps.remove(node.stepKey);
    }
    await save(
      current.copyWith(
        steps: steps,
        graph: current.graph.copyWith(
          nodes: current.graph.nodes.where((n) => n.id != nodeId).toList(),
          edges: current.graph.edges
              .where((edge) => edge.source != nodeId && edge.target != nodeId)
              .toList(),
        ),
      ),
    );
  }
}

WorkflowDocument _defaultWorkflow({
  required String name,
  required DateTime now,
}) {
  final stepKey = 'step_${getNewUuid().substring(0, 8)}';
  final requestId = getNewUuid();
  final nodeId = 'node_${getNewUuid().substring(0, 8)}';
  const label = 'Request 1';
  return WorkflowDocument(
    id: name,
    name: name,
    createdAt: now,
    modifiedAt: now,
    steps: {
      stepKey: WorkflowStep(
        label: label,
        request: RequestModel(
          id: requestId,
          name: label,
          httpRequestModel: const HttpRequestModel(
            method: HTTPVerb.get,
            url: 'https://',
          ),
        ).toJson(),
      ),
    },
    graph: WorkflowGraph(
      nodes: [
        const WorkflowGraphNode(
          id: 'start',
          type: WorkflowNodeType.manualStart,
          label: 'Start',
          position: WorkflowPosition(x: 80, y: 180),
        ),
        WorkflowGraphNode(
          id: nodeId,
          type: WorkflowNodeType.request,
          stepKey: stepKey,
          label: label,
          position: const WorkflowPosition(x: 320, y: 180),
        ),
      ],
      edges: [
        WorkflowGraphEdge(
          id: 'edge_start',
          source: 'start',
          sourceHandle: WorkflowEdgeHandle.next,
          target: nodeId,
        ),
      ],
    ),
  );
}

WorkflowEdgeHandle _sourceHandleForNode(
  WorkflowDocument workflow,
  String sourceNodeId,
) {
  for (final node in workflow.graph.nodes) {
    if (node.id == sourceNodeId) {
      return switch (node.type) {
        WorkflowNodeType.manualStart => WorkflowEdgeHandle.next,
        WorkflowNodeType.loop => WorkflowEdgeHandle.next,
        WorkflowNodeType.condition => WorkflowEdgeHandle.then,
        _ => WorkflowEdgeHandle.success,
      };
    }
  }
  return WorkflowEdgeHandle.success;
}

final workflowRunnerProvider = Provider<WorkflowRunner>((ref) {
  return const WorkflowRunner();
});

Future<WorkflowRunResult?> runActiveWorkflow(WidgetRef ref) async {
  final workflow = ref.read(activeWorkflowProvider);
  if (workflow == null) {
    return null;
  }
  ref.read(workflowRunInProgressProvider.notifier).state = true;
  ref.read(workflowNodeRunResultsProvider.notifier).state = {};
  ref.read(workflowRunStepOrderProvider.notifier).state = [];
  final runner = ref.read(workflowRunnerProvider);
  try {
    final result = await runner.run(
      ref: ref,
      workflow: workflow,
      storage: workspaceStorage,
      onNodeUpdate: (nodeResult) {
        ref.read(workflowNodeRunResultsProvider.notifier).state = {
          ...ref.read(workflowNodeRunResultsProvider),
          nodeResult.nodeId: nodeResult,
        };
        final order = ref.read(workflowRunStepOrderProvider);
        if (!order.contains(nodeResult.nodeId)) {
          ref.read(workflowRunStepOrderProvider.notifier).state = [
            ...order,
            nodeResult.nodeId,
          ];
        }
      },
      shouldStop: () => !ref.read(workflowRunInProgressProvider),
    );
    return result;
  } finally {
    ref.read(workflowRunInProgressProvider.notifier).state = false;
  }
}
