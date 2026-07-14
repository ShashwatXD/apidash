import 'package:apidash/models/models.dart';
import 'package:apidash/utils/utils.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:flutter/material.dart';

enum WorkflowTemplate {
  chainRequests,
  branchOnStatus,
  repeatRequests,
}

class WorkflowTemplateInfo {
  const WorkflowTemplateInfo({
    required this.template,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final WorkflowTemplate template;
  final String title;
  final String subtitle;
  final IconData icon;
}

// ignore: avoid_classes_with_only_static_members
class WorkflowTemplates {
  static const templates = <WorkflowTemplateInfo>[
    WorkflowTemplateInfo(
      template: WorkflowTemplate.chainRequests,
      title: 'Pass data between steps',
      subtitle: 'Extract a value from one response and use it in the next request.',
      icon: Icons.link_rounded,
    ),
    WorkflowTemplateInfo(
      template: WorkflowTemplate.branchOnStatus,
      title: 'Branch on response',
      subtitle: 'Run different steps when a request succeeds or fails.',
      icon: Icons.call_split_rounded,
    ),
    WorkflowTemplateInfo(
      template: WorkflowTemplate.repeatRequests,
      title: 'Repeat a request',
      subtitle: 'Run the same request multiple times without setting up a list.',
      icon: Icons.repeat_rounded,
    ),
  ];

  static WorkflowDocument build({
    required WorkflowTemplate template,
    required String name,
    required DateTime now,
  }) {
    return switch (template) {
      WorkflowTemplate.chainRequests => _chainRequests(name: name, now: now),
      WorkflowTemplate.branchOnStatus => _branchOnStatus(name: name, now: now),
      WorkflowTemplate.repeatRequests => _repeatRequests(name: name, now: now),
    };
  }
}

WorkflowDocument _chainRequests({
  required String name,
  required DateTime now,
}) {
  final fetchUserKey = 'step_${getNewUuid().substring(0, 8)}';
  final fetchPostsKey = 'step_${getNewUuid().substring(0, 8)}';
  final fetchUserId = getNewUuid();
  final fetchPostsId = getNewUuid();
  const fetchUserLabel = 'Get user';
  const fetchPostsLabel = 'Get user posts';

  return WorkflowDocument(
    id: name,
    name: name,
    description: 'Fetch a user, extract their id, then load their posts.',
    createdAt: now,
    modifiedAt: now,
    steps: {
      fetchUserKey: WorkflowStep(
        label: fetchUserLabel,
        request: RequestModel(
          id: fetchUserId,
          name: fetchUserLabel,
          httpRequestModel: const HttpRequestModel(
            method: HTTPVerb.get,
            url: 'https://jsonplaceholder.typicode.com/users/1',
          ),
        ).toJson(),
      ),
      fetchPostsKey: WorkflowStep(
        label: fetchPostsLabel,
        request: RequestModel(
          id: fetchPostsId,
          name: fetchPostsLabel,
          httpRequestModel: const HttpRequestModel(
            method: HTTPVerb.get,
            url: 'https://jsonplaceholder.typicode.com/posts?userId={{userId}}',
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
          position: WorkflowPosition(x: 80, y: 200),
        ),
        WorkflowGraphNode(
          id: 'node_fetch_user',
          type: WorkflowNodeType.request,
          stepKey: fetchUserKey,
          label: fetchUserLabel,
          position: const WorkflowPosition(x: 340, y: 200),
          extractions: const [
            WorkflowExtraction(varName: 'userId', jsonPath: 'id'),
          ],
        ),
        WorkflowGraphNode(
          id: 'node_fetch_posts',
          type: WorkflowNodeType.request,
          stepKey: fetchPostsKey,
          label: fetchPostsLabel,
          position: const WorkflowPosition(x: 620, y: 200),
        ),
      ],
      edges: const [
        WorkflowGraphEdge(
          id: 'edge_start_user',
          source: 'start',
          sourceHandle: WorkflowEdgeHandle.next,
          target: 'node_fetch_user',
        ),
        WorkflowGraphEdge(
          id: 'edge_user_posts',
          source: 'node_fetch_user',
          sourceHandle: WorkflowEdgeHandle.success,
          target: 'node_fetch_posts',
        ),
      ],
    ),
  );
}

WorkflowDocument _branchOnStatus({
  required String name,
  required DateTime now,
}) {
  final probeKey = 'step_${getNewUuid().substring(0, 8)}';
  final successKey = 'step_${getNewUuid().substring(0, 8)}';
  final failureKey = 'step_${getNewUuid().substring(0, 8)}';
  const probeLabel = 'Check API';
  const successLabel = 'Success path';
  const failureLabel = 'Failure path';

  return WorkflowDocument(
    id: name,
    name: name,
    description: 'Branch to different requests based on the HTTP status code.',
    createdAt: now,
    modifiedAt: now,
    steps: {
      probeKey: WorkflowStep(
        label: probeLabel,
        request: RequestModel(
          id: getNewUuid(),
          name: probeLabel,
          httpRequestModel: const HttpRequestModel(
            method: HTTPVerb.get,
            url: 'https://httpbin.org/get',
          ),
        ).toJson(),
      ),
      successKey: WorkflowStep(
        label: successLabel,
        request: RequestModel(
          id: getNewUuid(),
          name: successLabel,
          httpRequestModel: const HttpRequestModel(
            method: HTTPVerb.get,
            url: 'https://httpbin.org/uuid',
          ),
        ).toJson(),
      ),
      failureKey: WorkflowStep(
        label: failureLabel,
        request: RequestModel(
          id: getNewUuid(),
          name: failureLabel,
          httpRequestModel: const HttpRequestModel(
            method: HTTPVerb.get,
            url: 'https://httpbin.org/status/500',
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
          position: WorkflowPosition(x: 80, y: 220),
        ),
        WorkflowGraphNode(
          id: 'node_probe',
          type: WorkflowNodeType.request,
          stepKey: probeKey,
          label: probeLabel,
          position: const WorkflowPosition(x: 320, y: 220),
        ),
        const WorkflowGraphNode(
          id: 'node_condition',
          type: WorkflowNodeType.condition,
          label: 'HTTP success?',
          position: WorkflowPosition(x: 580, y: 220),
          conditionExpression: 'status>=200&&status<300',
        ),
        WorkflowGraphNode(
          id: 'node_success',
          type: WorkflowNodeType.request,
          stepKey: successKey,
          label: successLabel,
          position: const WorkflowPosition(x: 860, y: 140),
        ),
        WorkflowGraphNode(
          id: 'node_failure',
          type: WorkflowNodeType.request,
          stepKey: failureKey,
          label: failureLabel,
          position: const WorkflowPosition(x: 860, y: 300),
        ),
      ],
      edges: const [
        WorkflowGraphEdge(
          id: 'edge_start_probe',
          source: 'start',
          sourceHandle: WorkflowEdgeHandle.next,
          target: 'node_probe',
        ),
        WorkflowGraphEdge(
          id: 'edge_probe_condition',
          source: 'node_probe',
          sourceHandle: WorkflowEdgeHandle.success,
          target: 'node_condition',
        ),
        WorkflowGraphEdge(
          id: 'edge_condition_success',
          source: 'node_condition',
          sourceHandle: WorkflowEdgeHandle.then,
          target: 'node_success',
        ),
        WorkflowGraphEdge(
          id: 'edge_condition_failure',
          source: 'node_condition',
          sourceHandle: WorkflowEdgeHandle.elseBranch,
          target: 'node_failure',
        ),
      ],
    ),
  );
}

WorkflowDocument _repeatRequests({
  required String name,
  required DateTime now,
}) {
  final requestKey = 'step_${getNewUuid().substring(0, 8)}';
  const requestLabel = 'Generate UUID';

  return WorkflowDocument(
    id: name,
    name: name,
    description: 'Repeat the same request 3 times using a repeat loop.',
    createdAt: now,
    modifiedAt: now,
    steps: {
      requestKey: WorkflowStep(
        label: requestLabel,
        request: RequestModel(
          id: getNewUuid(),
          name: requestLabel,
          httpRequestModel: const HttpRequestModel(
            method: HTTPVerb.get,
            url: 'https://httpbin.org/uuid',
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
          position: WorkflowPosition(x: 80, y: 200),
        ),
        const WorkflowGraphNode(
          id: 'node_loop',
          type: WorkflowNodeType.loop,
          label: 'Repeat 3 times',
          position: WorkflowPosition(x: 320, y: 200),
          loopMode: WorkflowLoopMode.repeat,
          loopMaxIterations: 3,
        ),
        WorkflowGraphNode(
          id: 'node_request',
          type: WorkflowNodeType.request,
          stepKey: requestKey,
          label: requestLabel,
          position: const WorkflowPosition(x: 600, y: 200),
        ),
      ],
      edges: const [
        WorkflowGraphEdge(
          id: 'edge_start_loop',
          source: 'start',
          sourceHandle: WorkflowEdgeHandle.next,
          target: 'node_loop',
        ),
        WorkflowGraphEdge(
          id: 'edge_loop_body',
          source: 'node_loop',
          sourceHandle: WorkflowEdgeHandle.next,
          target: 'node_request',
        ),
      ],
    ),
  );
}
