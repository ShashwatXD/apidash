import 'dart:math' as math;

import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/consts.dart';
import 'package:apidash/workflow/widgets/workflow_node_layout.dart';
import 'package:flutter/material.dart';


Map<String, Offset> computeWorkflowAutoArrangePositions(WorkflowGraph graph) {
  if (graph.nodes.isEmpty) {
    return const {};
  }

  const originX = 80.0;
  const originY = 120.0;
  const columnGap = 100.0;
  const rowGap = 56.0;

  final nodesById = {for (final node in graph.nodes) node.id: node};

  final outgoing =
      <String, List<({String target, WorkflowEdgeHandle handle})>>{};
  final incomingCount = <String, int>{
    for (final node in graph.nodes) node.id: 0,
  };

  for (final edge in graph.edges) {
    if (edge.source == edge.target) {
      continue;
    }
    outgoing
        .putIfAbsent(edge.source, () => [])
        .add((target: edge.target, handle: edge.sourceHandle));
    incomingCount[edge.target] = (incomingCount[edge.target] ?? 0) + 1;
  }

  final roots = <String>[
    for (final node in graph.nodes)
      if (node.type == WorkflowNodeType.manualStart) node.id,
  ];
  if (roots.isEmpty) {
    roots.addAll(
      graph.nodes
          .where((node) => (incomingCount[node.id] ?? 0) == 0)
          .map((node) => node.id),
    );
  }
  if (roots.isEmpty) {
    roots.add(graph.nodes.first.id);
  }

  final layers = <String, int>{};
  final rows = <String, double>{};

  bool isBranchHandle(WorkflowEdgeHandle handle) =>
      handle == WorkflowEdgeHandle.failure ||
      handle == WorkflowEdgeHandle.elseBranch;

  void assignLayer(String nodeId, int layer, Set<String> path) {
    if (path.contains(nodeId)) {
      return;
    }
    layers[nodeId] = math.max(layers[nodeId] ?? 0, layer);

    path.add(nodeId);
    final edges = outgoing[nodeId] ?? const [];
    for (final edge in edges) {
      if (isBranchHandle(edge.handle)) {
        continue;
      }
      assignLayer(edge.target, layer + 1, path);
    }
    path.remove(nodeId);
  }

  void assignBranchRows(String nodeId, int layer, double row, Set<String> path) {
    if (path.contains(nodeId)) {
      return;
    }
    layers[nodeId] = math.max(layers[nodeId] ?? 0, layer);
    rows[nodeId] = math.min(rows[nodeId] ?? row, row);

    path.add(nodeId);
    final edges = outgoing[nodeId] ?? const [];
    for (final edge in edges) {
      if (isBranchHandle(edge.handle)) {
        continue;
      }
      assignBranchRows(edge.target, layer + 1, row, path);
    }
    var branchRow = row + 1;
    for (final edge in edges) {
      if (!isBranchHandle(edge.handle)) {
        continue;
      }
      assignBranchRows(edge.target, layer + 1, branchRow, path);
      branchRow += 1;
    }
    path.remove(nodeId);
  }

  var rootRow = 0.0;
  for (final root in roots) {
    assignLayer(root, 0, {});
    assignBranchRows(root, layers[root] ?? 0, rootRow, {});
    rootRow += 2;
  }

  var maxLayer = layers.values.fold(0, math.max);
  var orphanRow = rootRow;
  for (final node in graph.nodes) {
    if (!layers.containsKey(node.id)) {
      maxLayer += 1;
      layers[node.id] = maxLayer;
      rows[node.id] = orphanRow++;
    } else {
      rows.putIfAbsent(node.id, () => orphanRow++);
    }
  }

  final columnWidth = <int, double>{};
  for (final entry in layers.entries) {
    final node = nodesById[entry.key];
    if (node == null) {
      continue;
    }
    final width = WorkflowNodeLayout.sizeFor(node).width;
    columnWidth[entry.value] = math.max(columnWidth[entry.value] ?? 0, width);
  }

  double xForColumn(int column) {
    var x = originX;
    for (var index = 0; index < column; index++) {
      x += (columnWidth[index] ?? kWorkflowRequestNodeWidth) + columnGap;
    }
    return x;
  }

  final nodesByColumn = <int, List<String>>{};
  for (final entry in layers.entries) {
    nodesByColumn.putIfAbsent(entry.value, () => []).add(entry.key);
  }

  final positions = <String, Offset>{};
  for (final columnEntry in nodesByColumn.entries) {
    final column = columnEntry.key;
    final nodeIds = columnEntry.value
      ..sort((a, b) => (rows[a] ?? 0).compareTo(rows[b] ?? 0));

    var y = originY;
    final x = xForColumn(column);
    for (final nodeId in nodeIds) {
      positions[nodeId] = Offset(x, y);
      final node = nodesById[nodeId];
      if (node != null) {
        y += WorkflowNodeLayout.sizeFor(node).height + rowGap;
      }
    }
  }

  return positions;
}
