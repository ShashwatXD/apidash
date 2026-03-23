/// Top-level workflow model for persistence.
class WorkflowModel {
  const WorkflowModel({
    required this.id,
    this.name = 'Untitled Workflow',
    this.description = '',
    required this.createdAt,
    required this.modifiedAt,
    this.graphData = const {},
  });

  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final Map<String, dynamic> graphData;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'graphData': graphData,
      };

  factory WorkflowModel.fromJson(Map<String, dynamic> json) => WorkflowModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled Workflow',
        description: json['description'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        graphData: (json['graphData'] as Map<String, dynamic>?) ?? {},
      );

  WorkflowModel copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? modifiedAt,
    Map<String, dynamic>? graphData,
  }) =>
      WorkflowModel(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        graphData: graphData ?? this.graphData,
      );
}
