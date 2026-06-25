import 'package:apidash/importer/import_dialog.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/providers/providers.dart';
import 'package:apidash/widgets/widgets.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apidash/consts.dart';

import '../../common_widgets/common_widgets.dart';
import '../../home_page/collection_pane.dart';
import '../workspace/mobile_workspace_selector.dart';

const _kAddCollection = '__add_collection__';
const _kRenameCollection = '__rename_collection__';
const _kDeleteCollection = '__delete_collection__';

class MobileCollectionPane extends ConsumerWidget {
  const MobileCollectionPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoSaveNotifierProvider);
    ref.watch(collectionsStateNotifierProvider);
    final collection = ref.watch(collectionStateNotifierProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (collection == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: kPt8l4 + kPb70,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MobileCollectionHeader(
            onAddRequest: () async {
              final collectionId = ref.read(selectedCollectionIdStateProvider);
              await ref
                  .read(collectionStateNotifierProvider.notifier)
                  .ensureActive(collectionId);
              ref.read(collectionStateNotifierProvider.notifier).add();
            },
            onImport: () => importToCollectionPane(context, ref, messenger),
          ),
          kVSpacer6,
          const Padding(padding: kPh8, child: EnvironmentDropdown()),
          kVSpacer10,
          SidebarFilter(
            filterHintText: kHintFilterByNameOrUrl,
            onFilterFieldChanged: (value) {
              ref.read(collectionSearchQueryProvider.notifier).state =
                  value.toLowerCase();
            },
          ),
          kVSpacer10,
          const Expanded(child: MobileRequestList()),
          kVSpacer5,
        ],
      ),
    );
  }
}

class MobileCollectionHeader extends ConsumerWidget {
  const MobileCollectionHeader({
    super.key,
    required this.onAddRequest,
    required this.onImport,
  });

  final VoidCallback onAddRequest;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mobileScaffoldKey = ref.read(mobileScaffoldKeyStateProvider);
    final collections = ref.watch(collectionsStateNotifierProvider)!;
    final collectionSequence = ref.watch(collectionSequenceProvider);
    final selectedId = ref.watch(selectedCollectionIdStateProvider);
    final selectedName = collections[selectedId]?.name ?? '';

    return Padding(
      padding: kPe8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MobileWorkspaceSelector(),
          kVSpacer5,
          Row(
            children: [
              Expanded(
                child: _MobileCollectionSelector(
                  collectionSequence: collectionSequence,
                  collections: collections,
                  selectedId: selectedId,
                  selectedName: selectedName,
                ),
              ),
              kHSpacer4,
              ElevatedButton(
                onPressed: onAddRequest,
                style: kButtonSidebarStyle,
                child: const Text(
                  kLabelPlusNew,
                  style: kTextStyleButton,
                ),
              ),
              kHSpacer4,
              SizedBox(
                width: 24,
                child: SidebarTopMenu(
                  tooltip: kLabelMoreOptions,
                  onSelected: (option) => switch (option) {
                    SidebarMenuOption.import => onImport(),
                  },
                ),
              ),
              IconButton(
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(36, 36),
                ),
                onPressed: () => mobileScaffoldKey.currentState?.closeDrawer(),
                icon: const Icon(Icons.chevron_left),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileCollectionSelector extends ConsumerWidget {
  const _MobileCollectionSelector({
    required this.collectionSequence,
    required this.collections,
    required this.selectedId,
    required this.selectedName,
  });

  final List<String> collectionSequence;
  final Map<String, CollectionModel> collections;
  final String selectedId;
  final String selectedName;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(kLabelDeleteCollection),
        content: Text('Delete "$selectedName" and all its requests?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(kLabelCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(ItemMenuOption.delete.label),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(collectionsStateNotifierProvider.notifier)
          .deleteCollection(selectedId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      tooltip: kLabelCollectionName,
      onSelected: (value) async {
        if (value == _kAddCollection) {
          await ref
              .read(collectionsStateNotifierProvider.notifier)
              .addCollection();
          return;
        }
        if (value == _kRenameCollection) {
          if (!context.mounted) return;
          showRenameDialog(
            context,
            kLabelRenameCollection,
            selectedName,
            (val) async {
              if (val.isEmpty) return;
              await ref
                  .read(collectionsStateNotifierProvider.notifier)
                  .renameCollection(selectedId, val);
            },
          );
          return;
        }
        if (value == _kDeleteCollection) {
          if (!context.mounted) return;
          await _confirmDelete(context, ref);
          return;
        }
        await ref
            .read(collectionStateNotifierProvider.notifier)
            .ensureActive(value);
      },
      itemBuilder: (context) => [
        for (final id in collectionSequence)
          CheckedPopupMenuItem<String>(
            value: id,
            checked: id == selectedId,
            child: Text(
              collections[id]?.name ?? id,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _kAddCollection,
          child: Text('Add collection'),
        ),
        const PopupMenuItem(
          value: _kRenameCollection,
          child: Text(kLabelRenameCollection),
        ),
        PopupMenuItem(
          value: _kDeleteCollection,
          enabled: collectionSequence.length > 1,
          child: Text(ItemMenuOption.delete.label),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            kHSpacer6,
            Expanded(
              child: Text(
                selectedName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Icon(
              Icons.unfold_more,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class MobileRequestList extends ConsumerStatefulWidget {
  const MobileRequestList({super.key});

  @override
  ConsumerState<MobileRequestList> createState() => _MobileRequestListState();
}

class _MobileRequestListState extends ConsumerState<MobileRequestList> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selected = ref.read(selectedCollectionIdStateProvider);
      ref.read(collectionsStateNotifierProvider.notifier).loadCollection(
            selected,
          );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collectionId = ref.watch(selectedCollectionIdStateProvider);
    ref.watch(collectionStateNotifierProvider);
    final collections = ref.watch(collectionsStateNotifierProvider)!;
    final collection = collections[collectionId];
    if (collection == null) {
      return const Center(child: CircularProgressIndicator());
    }

    ref.read(collectionsStateNotifierProvider.notifier).loadCollection(
          collectionId,
        );

    final sequence = ref.watch(requestSequenceProvider);
    final summaries = ref
        .read(collectionStateNotifierProvider.notifier)
        .summariesForSequence(collectionId, sequence);
    final filterQuery = ref.watch(collectionSearchQueryProvider).trim();
    final visibleSummaries = filterQuery.isEmpty
        ? summaries
        : summaries.where((summary) {
            return summary.url.toLowerCase().contains(filterQuery) ||
                summary.name.toLowerCase().contains(filterQuery);
          }).toList();

    final alwaysShowScrollbar = ref.watch(
      settingsProvider.select(
        (value) => value.alwaysShowCollectionPaneScrollbar,
      ),
    );

    return Scrollbar(
      controller: _controller,
      thumbVisibility: alwaysShowScrollbar ? true : null,
      radius: const Radius.circular(12),
      child: ListView(
        padding: kPe8,
        controller: _controller,
        children: [
          for (final summary in visibleSummaries)
            Padding(
              padding: kP1,
              child: RequestItem(
                summary: summary,
                collectionId: collectionId,
              ),
            ),
        ],
      ),
    );
  }
}
