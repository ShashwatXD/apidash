import 'package:apidash/consts.dart';
import 'package:apidash/models/models.dart';

enum WorkflowNodeType { request, condition, manualStart, loop, delay }

enum WorkflowLoopMode {
  forEach,
  repeat;

  static WorkflowLoopMode fromJson(String? value) {
    if (value == 'repeat') {
      return WorkflowLoopMode.repeat;
    }
    return WorkflowLoopMode.forEach;
  }

  String toJson() => this == WorkflowLoopMode.repeat ? 'repeat' : 'forEach';
}

enum WorkflowEdgeHandle {
  next,
  loopDone,
  success,
  failure,
  then,
  elseBranch,
  inPort,
}

class WorkflowPosition {
  const WorkflowPosition({this.x = 0, this.y = 0});

  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory WorkflowPosition.fromJson(Map<String, dynamic> json) =>
      WorkflowPosition(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
      );

  WorkflowPosition copyWith({double? x, double? y}) =>
      WorkflowPosition(x: x ?? this.x, y: y ?? this.y);
}

class WorkflowViewport {
  const WorkflowViewport({this.x = 0, this.y = 0, this.zoom = 1});

  final double x;
  final double y;
  final double zoom;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'zoom': zoom};

  factory WorkflowViewport.fromJson(Map<String, dynamic> json) =>
      WorkflowViewport(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
      );

  WorkflowViewport copyWith({double? x, double? y, double? zoom}) =>
      WorkflowViewport(
        x: x ?? this.x,
        y: y ?? this.y,
        zoom: zoom ?? this.zoom,
      );
}

class WorkflowFlowVariable {
  const WorkflowFlowVariable({
    required this.key,
    this.value = '',
    this.enabled = true,
    this.description = '',
  });

  final String key;
  final String value;
  final bool enabled;
  final String description;

  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'enabled': enabled,
        if (description.isNotEmpty) 'description': description,
      };

  factory WorkflowFlowVariable.fromJson(Map<String, dynamic> json) =>
      WorkflowFlowVariable(
        key: json['key']?.toString() ?? '',
        value: json['value']?.toString() ?? '',
        enabled: json['enabled'] as bool? ?? true,
        description: json['description']?.toString() ?? '',
      );

  WorkflowFlowVariable copyWith({
    String? key,
    String? value,
    bool? enabled,
    String? description,
  }) =>
      WorkflowFlowVariable(
        key: key ?? this.key,
        value: value ?? this.value,
        enabled: enabled ?? this.enabled,
        description: description ?? this.description,
      );
}

class WorkflowInheritFrom {
  const WorkflowInheritFrom({
    required this.collectionId,
    required this.requestId,
  });

  final String collectionId;
  final String requestId;

  Map<String, dynamic> toJson() => {
        'collectionId': collectionId,
        'requestId': requestId,
      };

  factory WorkflowInheritFrom.fromJson(Map<String, dynamic> json) =>
      WorkflowInheritFrom(
        collectionId: json['collectionId']?.toString() ?? '',
        requestId: json['requestId']?.toString() ?? '',
      );
}

class WorkflowExtraction {
  const WorkflowExtraction({
    required this.varName,
    required this.jsonPath,
    this.source = 'response.body',
  });

  final String varName;
  final String source;
  final String jsonPath;

  Map<String, dynamic> toJson() => {
        'var': varName,
        'source': source,
        'jsonPath': jsonPath,
      };

  factory WorkflowExtraction.fromJson(Map<String, dynamic> json) =>
      WorkflowExtraction(
        varName: json['var']?.toString() ?? '',
        source: json['source']?.toString() ?? 'response.body',
        jsonPath: json['jsonPath']?.toString() ?? '',
      );
}

class WorkflowStep {
  const WorkflowStep({
    required this.label,
    required this.request,
    this.inheritFrom,
  });

  final String label;
  final Map<String, dynamic> request;
  final WorkflowInheritFrom? inheritFrom;

  Map<String, dynamic> toJson() => {
        'label': label,
        'request': request,
        if (inheritFrom != null) 'inheritFrom': inheritFrom!.toJson(),
      };

  factory WorkflowStep.fromJson(Map<String, dynamic> json) => WorkflowStep(
        label: json['label']?.toString() ?? '',
        request: Map<String, dynamic>.from(
          (json['request'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value),
              ) ??
              const {},
        ),
        inheritFrom: json['inheritFrom'] is Map
            ? WorkflowInheritFrom.fromJson(
                Map<String, dynamic>.from(json['inheritFrom'] as Map),
              )
            : null,
      );

  WorkflowStep copyWith({
    String? label,
    Map<String, dynamic>? request,
    WorkflowInheritFrom? inheritFrom,
    bool clearInheritFrom = false,
  }) =>
      WorkflowStep(
        label: label ?? this.label,
        request: request ?? this.request,
        inheritFrom: clearInheritFrom ? null : inheritFrom ?? this.inheritFrom,
      );
}

class WorkflowGraphNode {
  const WorkflowGraphNode({
    required this.id,
    required this.type,
    required this.position,
    this.stepKey,
    this.label = '',
    this.conditionExpression,
    this.loopExpression,
    this.loopMaxIterations,
    this.loopMode = WorkflowLoopMode.forEach,
    this.delayMs,
    this.extractions = const [],
    this.onFailure = 'abort',
  });

  final String id;
  final WorkflowNodeType type;
  final WorkflowPosition position;
  final String? stepKey;
  final String label;
  final String? conditionExpression;
  final String? loopExpression;
  final int? loopMaxIterations;
  final WorkflowLoopMode loopMode;
  final int? delayMs;
  final List<WorkflowExtraction> extractions;
  final String onFailure;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'position': position.toJson(),
        if (stepKey != null) 'stepKey': stepKey,
        if (label.isNotEmpty) 'label': label,
        if (conditionExpression != null)
          'conditionExpression': conditionExpression,
        if (loopExpression != null) 'loopExpression': loopExpression,
        if (loopMaxIterations != null && loopMaxIterations! > 0)
          'loopMaxIterations': loopMaxIterations,
        if (loopMode != WorkflowLoopMode.forEach) 'loopMode': loopMode.toJson(),
        if (delayMs != null && delayMs! > 0) 'delayMs': delayMs,
        if (extractions.isNotEmpty)
          'extractions': extractions.map((e) => e.toJson()).toList(),
        if (onFailure != 'abort') 'onFailure': onFailure,
      };

  factory WorkflowGraphNode.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? WorkflowNodeType.request.name;
    final type = WorkflowNodeType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => WorkflowNodeType.request,
    );
    final extractionsRaw = json['extractions'];
    return WorkflowGraphNode(
      id: json['id']?.toString() ?? '',
      type: type,
      position: json['position'] is Map
          ? WorkflowPosition.fromJson(
              Map<String, dynamic>.from(json['position'] as Map),
            )
          : const WorkflowPosition(),
      stepKey: json['stepKey']?.toString(),
      label: json['label']?.toString() ?? '',
      conditionExpression: json['conditionExpression']?.toString(),
      loopExpression: json['loopExpression']?.toString(),
      loopMaxIterations: (json['loopMaxIterations'] as num?)?.toInt(),
      loopMode: WorkflowLoopMode.fromJson(json['loopMode']?.toString()),
      delayMs: (json['delayMs'] as num?)?.toInt(),
      extractions: extractionsRaw is List
          ? [
              for (final item in extractionsRaw)
                if (item is Map)
                  WorkflowExtraction.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
            ]
          : const [],
      onFailure: json['onFailure']?.toString() ?? 'abort',
    );
  }

  WorkflowGraphNode copyWith({
    String? id,
    WorkflowNodeType? type,
    WorkflowPosition? position,
    String? stepKey,
    String? label,
    String? conditionExpression,
    String? loopExpression,
    int? loopMaxIterations,
    bool clearLoopMaxIterations = false,
    bool clearLoopExpression = false,
    WorkflowLoopMode? loopMode,
    int? delayMs,
    bool clearDelayMs = false,
    List<WorkflowExtraction>? extractions,
    String? onFailure,
  }) =>
      WorkflowGraphNode(
        id: id ?? this.id,
        type: type ?? this.type,
        position: position ?? this.position,
        stepKey: stepKey ?? this.stepKey,
        label: label ?? this.label,
        conditionExpression: conditionExpression ?? this.conditionExpression,
        loopExpression: clearLoopExpression
            ? null
            : (loopExpression ?? this.loopExpression),
        loopMaxIterations: clearLoopMaxIterations
            ? null
            : (loopMaxIterations ?? this.loopMaxIterations),
        loopMode: loopMode ?? this.loopMode,
        delayMs: clearDelayMs ? null : (delayMs ?? this.delayMs),
        extractions: extractions ?? this.extractions,
        onFailure: onFailure ?? this.onFailure,
      );
}

class WorkflowGraphEdge {
  const WorkflowGraphEdge({
    required this.id,
    required this.source,
    required this.target,
    this.sourceHandle = WorkflowEdgeHandle.success,
    this.targetHandle = WorkflowEdgeHandle.inPort,
    this.label = '',
  });

  final String id;
  final String source;
  final String target;
  final WorkflowEdgeHandle sourceHandle;
  final WorkflowEdgeHandle targetHandle;
  final String label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'sourceHandle': _handleToJson(sourceHandle),
        'target': target,
        'targetHandle': _handleToJson(targetHandle),
        if (label.isNotEmpty) 'label': label,
      };

  factory WorkflowGraphEdge.fromJson(Map<String, dynamic> json) =>
      WorkflowGraphEdge(
        id: json['id']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        target: json['target']?.toString() ?? '',
        sourceHandle: _parseHandle(
          json['sourceHandle']?.toString(),
          WorkflowEdgeHandle.success,
        ),
        targetHandle: _parseHandle(
          json['targetHandle']?.toString(),
          WorkflowEdgeHandle.inPort,
        ),
        label: json['label']?.toString() ?? '',
      );

  WorkflowGraphEdge copyWith({
    String? id,
    String? source,
    String? target,
    WorkflowEdgeHandle? sourceHandle,
    WorkflowEdgeHandle? targetHandle,
    String? label,
  }) =>
      WorkflowGraphEdge(
        id: id ?? this.id,
        source: source ?? this.source,
        target: target ?? this.target,
        sourceHandle: sourceHandle ?? this.sourceHandle,
        targetHandle: targetHandle ?? this.targetHandle,
        label: label ?? this.label,
      );
}

String _handleToJson(WorkflowEdgeHandle handle) {
  return switch (handle) {
    WorkflowEdgeHandle.elseBranch => 'else',
    WorkflowEdgeHandle.inPort => 'in',
    WorkflowEdgeHandle.loopDone => 'done',
    _ => handle.name,
  };
}

WorkflowEdgeHandle _parseHandle(String? raw, WorkflowEdgeHandle fallback) {
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  if (raw == 'else') {
    return WorkflowEdgeHandle.elseBranch;
  }
  if (raw == 'in') {
    return WorkflowEdgeHandle.inPort;
  }
  if (raw == 'done') {
    return WorkflowEdgeHandle.loopDone;
  }
  return WorkflowEdgeHandle.values.firstWhere(
    (value) => value.name == raw,
    orElse: () => fallback,
  );
}

class WorkflowGraph {
  const WorkflowGraph({
    this.nodes = const [],
    this.edges = const [],
  });

  final List<WorkflowGraphNode> nodes;
  final List<WorkflowGraphEdge> edges;

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((node) => node.toJson()).toList(),
        'edges': edges.map((edge) => edge.toJson()).toList(),
      };

  factory WorkflowGraph.fromJson(Map<String, dynamic> json) {
    final nodesRaw = json['nodes'];
    final edgesRaw = json['edges'];
    return WorkflowGraph(
      nodes: nodesRaw is List
          ? [
              for (final item in nodesRaw)
                if (item is Map)
                  WorkflowGraphNode.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      edges: edgesRaw is List
          ? [
              for (final item in edgesRaw)
                if (item is Map)
                  WorkflowGraphEdge.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }

  WorkflowGraph copyWith({
    List<WorkflowGraphNode>? nodes,
    List<WorkflowGraphEdge>? edges,
  }) =>
      WorkflowGraph(
        nodes: nodes ?? this.nodes,
        edges: edges ?? this.edges,
      );
}

class WorkflowDocument {
  const WorkflowDocument({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    this.description = '',
    this.schemaVersion = kWorkspaceWorkflowSchemaVersion,
    this.viewport = const WorkflowViewport(),
    this.flowVariables = const [],
    this.steps = const {},
    this.graph = const WorkflowGraph(),
  });

  final int schemaVersion;
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final WorkflowViewport viewport;
  final List<WorkflowFlowVariable> flowVariables;
  final Map<String, WorkflowStep> steps;
  final WorkflowGraph graph;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        if (description.isNotEmpty) 'description': description,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'viewport': viewport.toJson(),
        if (flowVariables.isNotEmpty)
          'flowVariables': flowVariables.map((item) => item.toJson()).toList(),
        'steps': steps.map((key, value) => MapEntry(key, value.toJson())),
        'graph': graph.toJson(),
      };

  factory WorkflowDocument.fromJson(Map<String, dynamic> json) {
    final stepsRaw = json['steps'];
    final steps = <String, WorkflowStep>{};
    if (stepsRaw is Map) {
      for (final entry in stepsRaw.entries) {
        if (entry.value is Map) {
          steps[entry.key.toString()] = WorkflowStep.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    final flowVarsRaw = json['flowVariables'];
    return WorkflowDocument(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ??
          kWorkspaceWorkflowSchemaVersion,
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? kUntitled,
      description: json['description']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      modifiedAt: DateTime.tryParse(json['modifiedAt']?.toString() ?? '') ??
          DateTime.now(),
      viewport: json['viewport'] is Map
          ? WorkflowViewport.fromJson(
              Map<String, dynamic>.from(json['viewport'] as Map),
            )
          : const WorkflowViewport(),
      flowVariables: flowVarsRaw is List
          ? [
              for (final item in flowVarsRaw)
                if (item is Map)
                  WorkflowFlowVariable.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
            ]
          : const [],
      steps: steps,
      graph: json['graph'] is Map
          ? WorkflowGraph.fromJson(
              Map<String, dynamic>.from(json['graph'] as Map),
            )
          : const WorkflowGraph(),
    );
  }

  WorkflowDocument copyWith({
    int? schemaVersion,
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? modifiedAt,
    WorkflowViewport? viewport,
    List<WorkflowFlowVariable>? flowVariables,
    Map<String, WorkflowStep>? steps,
    WorkflowGraph? graph,
  }) =>
      WorkflowDocument(
        schemaVersion: schemaVersion ?? this.schemaVersion,
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        viewport: viewport ?? this.viewport,
        flowVariables: flowVariables ?? this.flowVariables,
        steps: steps ?? this.steps,
        graph: graph ?? this.graph,
      );

  WorkflowStep? stepForNode(WorkflowGraphNode node) {
    final key = node.stepKey;
    if (key == null || key.isEmpty) {
      return null;
    }
    return steps[key];
  }

  RequestModel? requestModelForStep(String stepKey) {
    final step = steps[stepKey];
    if (step == null) {
      return null;
    }
    try {
      return RequestModel.fromJson(Map<String, Object?>.from(step.request));
    } catch (_) {
      return null;
    }
  }
}

enum WorkflowNodeRunStatus { pending, running, success, failed, skipped }

class WorkflowNodeRunResult {
  const WorkflowNodeRunResult({
    required this.nodeId,
    required this.status,
    this.label = '',
    this.message,
    this.durationMs,
    this.statusCode,
    this.loopIndex,
  });

  final String nodeId;
  final String label;
  final WorkflowNodeRunStatus status;
  final String? message;
  final int? durationMs;
  final int? statusCode;
  /// Present when this result is one iteration of a loop body.
  final String? loopIndex;
}

class WorkflowRunResult {
  const WorkflowRunResult({
    required this.workflowId,
    required this.success,
    required this.startedAt,
    required this.endedAt,
    required this.nodeResults,
    this.error,
    this.scopedVariables = const {},
  });

  final String workflowId;
  final bool success;
  final DateTime startedAt;
  final DateTime endedAt;
  final String? error;
  final List<WorkflowNodeRunResult> nodeResults;
  final Map<String, String> scopedVariables;

  int get durationMs => endedAt.difference(startedAt).inMilliseconds;
}
