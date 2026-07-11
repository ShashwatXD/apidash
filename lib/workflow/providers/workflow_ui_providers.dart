import 'package:flutter_riverpod/legacy.dart';

final selectedWorkflowNodeIdProvider = StateProvider<String?>((ref) => null);

typedef WorkflowInspectorFlush = Future<void> Function();

final workflowInspectorFlushProvider =
    StateProvider<WorkflowInspectorFlush?>((ref) => null);
