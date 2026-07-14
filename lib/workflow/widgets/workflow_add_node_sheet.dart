import 'package:apidash/consts.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:apidash/workflow/models/workflow_models.dart';
import 'package:apidash/workflow/widgets/workflow_logic_node_editor.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _AddNodePage {
  nodeTypes,
  httpRequestSource,
  aiRequestSource,
  importCollection,
}

Future<void> showWorkflowAddNodeSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _WorkflowAddNodeSheet(
      parentRef: ref,
      sheetContext: sheetContext,
    ),
  );
}

class _WorkflowAddNodeSheet extends ConsumerStatefulWidget {
  const _WorkflowAddNodeSheet({
    required this.parentRef,
    required this.sheetContext,
  });

  final WidgetRef parentRef;
  final BuildContext sheetContext;

  @override
  ConsumerState<_WorkflowAddNodeSheet> createState() =>
      _WorkflowAddNodeSheetState();
}

class _WorkflowAddNodeSheetState extends ConsumerState<_WorkflowAddNodeSheet> {
  _AddNodePage _page = _AddNodePage.nodeTypes;
  _AddNodePage _importReturnPage = _AddNodePage.httpRequestSource;
  APIType? _importApiTypeFilter;

  Offset _placementPosition() {
    final workflow = ref.read(activeWorkflowProvider);
    if (workflow == null) {
      return const Offset(280, 180);
    }
    final selectedId = ref.read(selectedWorkflowNodeIdProvider);
    if (selectedId != null) {
      for (final node in workflow.graph.nodes) {
        if (node.id == selectedId) {
          return Offset(node.position.x + 48, node.position.y + 140);
        }
      }
    }
    if (workflow.graph.nodes.isNotEmpty) {
      final last = workflow.graph.nodes.last;
      return Offset(last.position.x + 48, last.position.y + 48);
    }
    return const Offset(280, 180);
  }

  void _closeSheet() {
    Navigator.of(widget.sheetContext).pop();
  }

  void _openImportCollections({
    required _AddNodePage returnPage,
    required APIType? apiTypeFilter,
  }) {
    ref.read(collectionCatalogProvider.notifier).reloadAllCollectionsFromDisk();
    setState(() {
      _importReturnPage = returnPage;
      _importApiTypeFilter = apiTypeFilter;
      _page = _AddNodePage.importCollection;
    });
  }

  Future<void> _openNodeEditor(String? nodeId) async {
    if (nodeId == null) {
      return;
    }
    final workflow = ref.read(activeWorkflowProvider);
    if (workflow == null) {
      return;
    }
    WorkflowGraphNode? node;
    for (final candidate in workflow.graph.nodes) {
      if (candidate.id == nodeId) {
        node = candidate;
        break;
      }
    }
    if (node == null || !widget.sheetContext.mounted) {
      return;
    }
    await openWorkflowNodeEditor(
      widget.sheetContext,
      widget.parentRef,
      node: node,
    );
  }

  Future<void> _addLoopNode() async {
    final nodeId = await ref.read(activeWorkflowProvider.notifier).addLoopNode(
          position: _placementPosition(),
        );
    if (!mounted) {
      return;
    }
    _closeSheet();
    await _openNodeEditor(nodeId);
  }

  Future<void> _addConditionNode() async {
    final nodeId =
        await ref.read(activeWorkflowProvider.notifier).addConditionNode(
              position: _placementPosition(),
            );
    if (!mounted) {
      return;
    }
    _closeSheet();
    await _openNodeEditor(nodeId);
  }

  Future<void> _createNewRequest({APIType apiType = APIType.rest}) async {
    final nodeId = await ref.read(activeWorkflowProvider.notifier).addRequestStep(
          position: _placementPosition(),
          apiType: apiType,
        );
    if (!mounted) {
      return;
    }
    _closeSheet();
    await _openNodeEditor(nodeId);
  }

  Future<void> _importRequest({
    required String collectionId,
    required String requestId,
  }) async {
    final nodeId =
        await ref.read(activeWorkflowProvider.notifier).importRequestFromCollection(
              collectionId: collectionId,
              requestId: requestId,
              position: _placementPosition(),
            );
    if (!mounted || nodeId == null) {
      return;
    }
    _closeSheet();
  }

  bool _matchesImportFilter(APIType apiType) {
    final filter = _importApiTypeFilter;
    if (filter == null) {
      return true;
    }
    if (filter == APIType.ai) {
      return apiType == APIType.ai;
    }
    return apiType != APIType.ai;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme),
            Flexible(
              child: switch (_page) {
                _AddNodePage.nodeTypes => _buildNodeTypeList(theme),
                _AddNodePage.httpRequestSource =>
                  _buildHttpRequestSourceList(theme),
                _AddNodePage.aiRequestSource => _buildAiRequestSourceList(theme),
                _AddNodePage.importCollection =>
                  _buildImportCollectionList(theme),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final title = switch (_page) {
      _AddNodePage.nodeTypes => kLabelAddWorkflowNode,
      _AddNodePage.httpRequestSource => kLabelHttpRequest,
      _AddNodePage.aiRequestSource => kLabelAiRequest,
      _AddNodePage.importCollection => switch (_importApiTypeFilter) {
        APIType.ai => '$kLabelImportFromCollection · $kLabelAiRequest',
        _ => '$kLabelImportFromCollection · $kLabelHttpRequest',
      },
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          if (_page != _AddNodePage.nodeTypes)
            IconButton(
              tooltip: 'Back',
              onPressed: () => setState(() {
                _page = switch (_page) {
                  _AddNodePage.importCollection => _importReturnPage,
                  _ => _AddNodePage.nodeTypes,
                };
              }),
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: kLabelCancel,
            onPressed: _closeSheet,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTypeList(ThemeData theme) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'Choose what to add to the canvas',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _AddNodeOptionTile(
          icon: Icons.auto_awesome_rounded,
          iconColor: theme.colorScheme.tertiary,
          title: kLabelAiRequest,
          subtitle: 'Import an AI request from a collection or start blank',
          showChevron: true,
          onTap: () => setState(() => _page = _AddNodePage.aiRequestSource),
        ),
        const SizedBox(height: 8),
        _AddNodeOptionTile(
          icon: Icons.http_rounded,
          iconColor: theme.colorScheme.primary,
          title: kLabelHttpRequest,
          subtitle: 'Import an HTTP request from a collection or start blank',
          showChevron: true,
          onTap: () => setState(() => _page = _AddNodePage.httpRequestSource),
        ),
        const SizedBox(height: 8),
        _AddNodeOptionTile(
          icon: Icons.loop_rounded,
          iconColor: theme.colorScheme.secondary,
          title: kLabelWorkflowLoop,
          subtitle: 'Repeat steps for each list item, or the same step N times',
          onTap: _addLoopNode,
        ),
        const SizedBox(height: 8),
        _AddNodeOptionTile(
          icon: Icons.rule_rounded,
          iconColor: theme.colorScheme.tertiary,
          title: kLabelWorkflowCondition,
          subtitle: 'Branch the flow on true / false conditions',
          onTap: _addConditionNode,
        ),
      ],
    );
  }

  Widget _buildHttpRequestSourceList(ThemeData theme) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'How do you want to create this HTTP step?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _AddNodeOptionTile(
          icon: Icons.folder_copy_outlined,
          iconColor: theme.colorScheme.primary,
          title: kLabelImportFromCollection,
          subtitle: 'Reuse an existing HTTP request from your collections',
          showChevron: true,
          onTap: () => _openImportCollections(
            returnPage: _AddNodePage.httpRequestSource,
            apiTypeFilter: APIType.rest,
          ),
        ),
        const SizedBox(height: 8),
        _AddNodeOptionTile(
          icon: Icons.add_circle_outline_rounded,
          iconColor: theme.colorScheme.primary,
          title: kLabelCreateNewRequest,
          subtitle: 'Blank GET request — configure URL, headers, and body',
          onTap: () => _createNewRequest(),
        ),
      ],
    );
  }

  Widget _buildAiRequestSourceList(ThemeData theme) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'How do you want to create this AI step?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _AddNodeOptionTile(
          icon: Icons.folder_copy_outlined,
          iconColor: theme.colorScheme.tertiary,
          title: kLabelImportFromCollection,
          subtitle: 'Reuse an existing AI request from your collections',
          showChevron: true,
          onTap: () => _openImportCollections(
            returnPage: _AddNodePage.aiRequestSource,
            apiTypeFilter: APIType.ai,
          ),
        ),
        const SizedBox(height: 8),
        _AddNodeOptionTile(
          icon: Icons.add_circle_outline_rounded,
          iconColor: theme.colorScheme.tertiary,
          title: kLabelCreateNewAiRequest,
          subtitle: 'Blank AI prompt step — pick a model and configure prompts',
          onTap: () => _createNewRequest(apiType: APIType.ai),
        ),
      ],
    );
  }

  Widget _buildImportCollectionList(ThemeData theme) {
    final catalog = ref.watch(collectionCatalogProvider);
    if (catalog == null || catalog.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No collections yet',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Create a collection with requests first, then import them here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final tiles = <Widget>[];
    for (final entry in catalog.entries) {
      final collection = entry.value;
      final matchingRequests = collection.requests
          .where((summary) => _matchesImportFilter(summary.apiType))
          .toList();
      if (matchingRequests.isEmpty) {
        continue;
      }
      tiles.add(
        ExpansionTile(
          key: PageStorageKey('${entry.key}_${_importApiTypeFilter?.name}'),
          leading: const Icon(Icons.folder_outlined),
          title: Text(collection.name),
          subtitle: Text('${matchingRequests.length} requests'),
          children: [
            for (final summary in matchingRequests)
              ListTile(
                leading: Icon(
                  summary.apiType == APIType.ai
                      ? Icons.auto_awesome_rounded
                      : Icons.link_rounded,
                  size: 20,
                ),
                title: Text(summary.name),
                subtitle: Text(
                  summary.apiType == APIType.ai
                      ? kLabelAiRequest
                      : summary.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _importRequest(
                  collectionId: entry.key,
                  requestId: summary.id,
                ),
              ),
          ],
        ),
      );
    }

    if (tiles.isEmpty) {
      final emptyLabel = _importApiTypeFilter == APIType.ai
          ? 'No AI requests found in your collections.'
          : 'No HTTP requests found in your collections.';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              emptyLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      children: tiles,
    );
  }
}

class _AddNodeOptionTile extends StatelessWidget {
  const _AddNodeOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.showChevron = false,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (iconColor ?? theme.colorScheme.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              kHSpacer12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (showChevron)
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
