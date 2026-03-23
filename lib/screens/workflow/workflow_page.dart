import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/providers/providers.dart';

/// Workflow builder POC: canvas with Start, Request, End nodes and minimal run.
class WorkflowPage extends ConsumerStatefulWidget {
  const WorkflowPage({super.key});

  @override
  ConsumerState<WorkflowPage> createState() => _WorkflowPageState();
}

class _WorkflowPageState extends ConsumerState<WorkflowPage> {
  late final NodeFlowController<WorkflowNodeData, dynamic> _controller;
  bool _isRunning = false;
  String? _runningNodeId;
  final Map<String, bool> _nodeSuccess = {};
  final Map<String, _NodeRunOutput> _nodeOutputs = {};
  int _nodeCounter = 100;
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _controller = NodeFlowController<WorkflowNodeData, dynamic>(
      nodes: _defaultNodes(),
      connections: _defaultConnections(),
    );
  }

  List<Node<WorkflowNodeData>> _defaultNodes() {
    return [
      Node<WorkflowNodeData>(
        id: 'start-1',
        type: 'start',
        position: const Offset(80, 120),
        data: const WorkflowNodeData(
          nodeType: WorkflowNodeType.start,
          label: 'Start',
        ),
        ports: [
          Port(
            id: 'next',
            name: 'Next',
            position: PortPosition.right,
            type: PortType.output,
            offset: const Offset(0, 50),
          ),
        ],
      ),
      Node<WorkflowNodeData>(
        id: 'request-1',
        type: 'request',
        position: const Offset(280, 100),
        data: const WorkflowNodeData(
          nodeType: WorkflowNodeType.request,
          label: 'Request',
        ),
        ports: [
          Port(
            id: 'trigger',
            name: 'In',
            position: PortPosition.left,
            type: PortType.input,
            offset: const Offset(0, 50),
          ),
          Port(
            id: 'out',
            name: 'Out',
            position: PortPosition.right,
            type: PortType.output,
            offset: const Offset(0, 50),
          ),
        ],
      ),
      Node<WorkflowNodeData>(
        id: 'end-1',
        type: 'end',
        position: const Offset(480, 120),
        data: const WorkflowNodeData(
          nodeType: WorkflowNodeType.end,
          label: 'End',
        ),
        ports: [
          Port(
            id: 'in',
            name: 'In',
            position: PortPosition.left,
            type: PortType.input,
            offset: const Offset(0, 50),
          ),
        ],
      ),
    ];
  }

  List<Connection<dynamic>> _defaultConnections() {
    return [
      Connection(
        id: 'c1',
        sourceNodeId: 'start-1',
        sourcePortId: 'next',
        targetNodeId: 'request-1',
        targetPortId: 'trigger',
      ),
      Connection(
        id: 'c2',
        sourceNodeId: 'request-1',
        sourcePortId: 'out',
        targetNodeId: 'end-1',
        targetPortId: 'in',
      ),
    ];
  }

  Node<WorkflowNodeData> _createNode({
    required WorkflowNodeType nodeType,
    required Offset position,
    String? id,
  }) {
    final nodeId = id ?? '${nodeType.name}-${_nodeCounter++}';

    final ports = switch (nodeType) {
      WorkflowNodeType.start => [
        Port(
          id: 'next',
          name: 'Next',
          position: PortPosition.right,
          type: PortType.output,
          offset: const Offset(0, 50),
        ),
      ],
      WorkflowNodeType.request => [
        Port(
          id: 'trigger',
          name: 'In',
          position: PortPosition.left,
          type: PortType.input,
          offset: const Offset(0, 50),
        ),
        Port(
          id: 'out',
          name: 'Out',
          position: PortPosition.right,
          type: PortType.output,
          offset: const Offset(0, 50),
        ),
      ],
      WorkflowNodeType.end => [
        Port(
          id: 'in',
          name: 'In',
          position: PortPosition.left,
          type: PortType.input,
          offset: const Offset(0, 50),
        ),
      ],
    };

    return Node<WorkflowNodeData>(
      id: nodeId,
      type: nodeType.name,
      position: position,
      data: WorkflowNodeData(
        nodeType: nodeType,
        label: _defaultLabel(nodeType),
      ),
      ports: ports,
    );
  }

  String _defaultLabel(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.start:
        return 'Start';
      case WorkflowNodeType.request:
        return 'Request';
      case WorkflowNodeType.end:
        return 'End';
    }
  }

  void _addNode(WorkflowNodeType type) {
    final center = _controller.getViewportCenter();
    final node = _createNode(nodeType: type, position: center.offset);
    _controller.addNode(node);
    setState(() => _selectedNodeId = node.id);
  }

  void _updateSelectedNodeData(WorkflowNodeData newData) {
    final nodeId = _selectedNodeId;
    if (nodeId == null) return;
    final existing = _controller.nodes[nodeId];
    if (existing == null) return;

    final replacement = Node<WorkflowNodeData>(
      id: existing.id,
      type: existing.type,
      position: existing.position.value,
      data: newData,
      ports: existing.ports,
      size: existing.size.value,
      initialZIndex: existing.zIndex.value,
      theme: existing.theme,
      widgetBuilder: existing.widgetBuilder,
    );

    _controller.addNode(replacement);
  }

  Future<void> _runWorkflow() async {
    if (_isRunning) return;
    final collection = ref.read(collectionStateNotifierProvider);
    if (collection == null || collection.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one request in the collection.')),
        );
      }
      return;
    }

    setState(() {
      _isRunning = true;
      _runningNodeId = null;
      _nodeSuccess.clear();
    });

    final startNode = _pickRunnableStartNode();
    if (startNode == null) {
      setState(() => _isRunning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No runnable node found. Add/Select a Request node.')),
        );
      }
      return;
    }

    final previousSelectedId = ref.read(selectedIdStateProvider);

    try {
      await _runFromNode(startNodeId: startNode.id, collection: collection);
    } finally {
      ref.read(selectedIdStateProvider.notifier).state = previousSelectedId;
      setState(() => _isRunning = false);
    }
  }

  Node<WorkflowNodeData>? _pickRunnableStartNode() {
    // 1) If user selected a Request node, start there.
    final selectedId = _selectedNodeId;
    if (selectedId != null) {
      final sel = _controller.nodes[selectedId];
      if (sel != null && sel.data.nodeType == WorkflowNodeType.request) {
        return sel;
      }
    }

    // 2) If graph has a Start node, start from it.
    final start = _controller.nodes.values
        .cast<Node<WorkflowNodeData>>()
        .where((n) => n.data.nodeType == WorkflowNodeType.start)
        .toList();
    if (start.isNotEmpty) {
      return start.first;
    }

    // 3) Fallback: if there's any Request node, start from it.
    final requestNodes = _controller.nodes.values
        .where((n) => n.data.nodeType == WorkflowNodeType.request)
        .toList();
    return requestNodes.isNotEmpty ? requestNodes.first : null;
  }

  Future<void> _runFromNode({
    required String startNodeId,
    required Map<String, dynamic> collection,
  }) async {
    final visited = <String>{};
    var current = _controller.nodes[startNodeId];

    while (current != null && !visited.contains(current.id)) {
      visited.add(current.id);

      if (current.data.nodeType == WorkflowNodeType.end) {
        setState(() => _runningNodeId = null);
        return;
      }

      if (current.data.nodeType == WorkflowNodeType.request) {
        final ok = await _runSingleRequestNode(current, collection);
        if (!ok) return; // stop on first failure for now (clear demo behavior)
      }

      current = _nextNodeFrom(current.id);
    }
  }

  Future<bool> _runSingleRequestNode(
    Node<WorkflowNodeData> requestNode,
    Map<String, dynamic> collection,
  ) async {
    String? linkedId = requestNode.data.linkedRequestId;
    if (linkedId == null || linkedId.isEmpty) {
      linkedId = collection.keys.first;
    }
    if (!collection.containsKey(linkedId)) {
      setState(() {
        _nodeSuccess[requestNode.id] = false;
        _runningNodeId = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Linked request not found in collection.')),
        );
      }
      return false;
    }

    ref.read(selectedIdStateProvider.notifier).state = linkedId;
    setState(() => _runningNodeId = requestNode.id);

    try {
      await ref.read(collectionStateNotifierProvider.notifier).sendRequest();
      final col = ref.read(collectionStateNotifierProvider);
      final req = col != null ? col[linkedId] : null;
      final status = req?.responseStatus;
      final timeMs = req?.httpResponseModel?.time?.inMilliseconds;
      final body =
          req?.httpResponseModel?.formattedBody ?? req?.httpResponseModel?.body;
      final ok = status != null && status >= 200 && status < 300;
      setState(() {
        _nodeSuccess[requestNode.id] = ok;
        _nodeOutputs[requestNode.id] = _NodeRunOutput(
          requestId: linkedId!,
          statusCode: status,
          timeMs: timeMs,
          bodyPreview: body != null && body.length > 600 ? '${body.substring(0, 600)}...' : body,
        );
        _runningNodeId = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Request completed ($status${timeMs != null ? ', ${timeMs}ms' : ''})'
                  : 'Request failed ($status${timeMs != null ? ', ${timeMs}ms' : ''})',
            ),
          ),
        );
      }
      return ok;
    } catch (e) {
      setState(() {
        _nodeSuccess[requestNode.id] = false;
        _nodeOutputs[requestNode.id] = _NodeRunOutput(
          requestId: linkedId ?? '',
          statusCode: null,
          timeMs: null,
          bodyPreview: 'Error: $e',
        );
        _runningNodeId = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      return false;
    }
  }

  Node<WorkflowNodeData>? _nextNodeFrom(String nodeId) {
    for (final c in _controller.connections) {
      if (c.sourceNodeId == nodeId) {
        final target = _controller.nodes[c.targetNodeId];
        if (target != null) return target;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nodeFlowTheme = isDark ? NodeFlowTheme.dark : NodeFlowTheme.light;
    final collection = ref.watch(collectionStateNotifierProvider);
    final selectedNode =
        _selectedNodeId != null ? _controller.nodes[_selectedNodeId!] : null;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Workflow',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _isRunning ? null : _runWorkflow,
                  icon: _isRunning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow, size: 20),
                  label: Text(_isRunning ? 'Running...' : 'Run'),
                ),
              ],
            ),
          ),
          Expanded(
            child: NodeFlowEditor<WorkflowNodeData, dynamic>(
              controller: _controller,
              theme: nodeFlowTheme,
              nodeBuilder: (context, node) => _WorkflowNodeWidget(
                node: node,
                isRunning: _runningNodeId == node.id,
                isSuccess: _nodeSuccess[node.id],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeRunOutput {
  const _NodeRunOutput({
    required this.requestId,
    required this.statusCode,
    required this.timeMs,
    required this.bodyPreview,
  });

  final String requestId;
  final int? statusCode;
  final int? timeMs;
  final String? bodyPreview;
}

class _WorkflowNodeWidget extends StatelessWidget {
  const _WorkflowNodeWidget({
    required this.node,
    required this.isRunning,
    required this.isSuccess,
  });

  final Node<WorkflowNodeData> node;
  final bool isRunning;
  final bool? isSuccess;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = node.data;
    Color bg = theme.colorScheme.surfaceContainerHigh;
    IconData icon = Icons.circle;
    final label = d.label.isEmpty ? _defaultLabel(d.nodeType) : d.label;

    if (isRunning) {
      bg = theme.colorScheme.primaryContainer;
      icon = Icons.hourglass_empty;
    } else if (isSuccess == true) {
      bg = theme.colorScheme.primaryContainer;
      icon = Icons.check_circle;
    } else if (isSuccess == false) {
      bg = theme.colorScheme.errorContainer;
      icon = Icons.error;
    } else {
      switch (d.nodeType) {
        case WorkflowNodeType.start:
          bg = theme.colorScheme.tertiaryContainer;
          icon = Icons.play_arrow;
          break;
        case WorkflowNodeType.request:
          bg = theme.colorScheme.secondaryContainer;
          icon = Icons.http;
          break;
        case WorkflowNodeType.end:
          bg = theme.colorScheme.surfaceContainerHigh;
          icon = Icons.stop_circle;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRunning ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.3),
          width: isRunning ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.onSurface),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }

  String _defaultLabel(WorkflowNodeType type) {
    switch (type) {
      case WorkflowNodeType.start:
        return 'Start';
      case WorkflowNodeType.request:
        return 'Request';
      case WorkflowNodeType.end:
        return 'End';
    }
  }
}
