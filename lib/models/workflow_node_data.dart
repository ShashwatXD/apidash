/// Node type for workflow builder POC.
enum WorkflowNodeType {
  start,
  request,
  end,
}

/// Data carried by each node in the workflow canvas.
class WorkflowNodeData {
  const WorkflowNodeData({
    required this.nodeType,
    this.label = '',
    this.linkedRequestId,
  });

  final WorkflowNodeType nodeType;
  final String label;
  final String? linkedRequestId;

  Map<String, dynamic> toJson() => {
        'nodeType': nodeType.name,
        'label': label,
        if (linkedRequestId != null) 'linkedRequestId': linkedRequestId,
      };

  factory WorkflowNodeData.fromJson(Map<String, dynamic> json) {
    final typeStr = json['nodeType'] as String? ?? 'start';
    WorkflowNodeType type;
    switch (typeStr) {
      case 'request':
        type = WorkflowNodeType.request;
        break;
      case 'end':
        type = WorkflowNodeType.end;
        break;
      default:
        type = WorkflowNodeType.start;
    }
    return WorkflowNodeData(
      nodeType: type,
      label: json['label'] as String? ?? '',
      linkedRequestId: json['linkedRequestId'] as String?,
    );
  }

  WorkflowNodeData copyWith({
    WorkflowNodeType? nodeType,
    String? label,
    String? linkedRequestId,
  }) =>
      WorkflowNodeData(
        nodeType: nodeType ?? this.nodeType,
        label: label ?? this.label,
        linkedRequestId: linkedRequestId ?? this.linkedRequestId,
      );
}
