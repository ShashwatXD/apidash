import 'dart:async';
import 'dart:io';

import 'package:apidash/consts.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;

import '../services/services.dart';
import 'active_collection_providers.dart';
import 'settings_providers.dart';

final selectedCollectionIdStateProvider = StateProvider<String?>((ref) {
  final index = workspaceStorage.getCollectionsIndex();
  if (index.isNotEmpty) {
    return index.first.id;
  }
  return null;
});

final collectionSequenceProvider = Provider<List<String>>((ref) {
  ref.watch(collectionCatalogProvider);
  return ref.read(collectionCatalogProvider.notifier).collectionSequence;
});

final requestSequenceProvider = StateProvider<List<String>>((ref) => []);

final expandedCollectionIdsProvider = StateProvider<Set<String>>((ref) => {});

final StateNotifierProvider<CollectionCatalogNotifier, Map<String, CollectionModel>?>
collectionCatalogProvider = StateNotifierProvider(
  (ref) => CollectionCatalogNotifier(ref, workspaceStorage),
);

class CollectionCatalogNotifier
    extends StateNotifier<Map<String, CollectionModel>?> {
  CollectionCatalogNotifier(this.ref, this.workspaceStorage) : super(null) {
    final index = _readCollectionsIndex();

    collectionSequence = index.map((e) => e.id).toList();
    state = {
      for (final entry in index)
        entry.id: CollectionModel(id: entry.id, name: entry.id),
    };
    final active = ref.read(selectedCollectionIdStateProvider);
    if (active != null) {
      loadCollection(active);
    }
  }

  final Ref ref;
  final WorkspaceStorage workspaceStorage;
  List<String> collectionSequence = [];
  final Set<String> _loadedCollectionIds = {};

  List<({String id, String name})> _readCollectionsIndex() {
    return workspaceStorage.getCollectionsIndex();
  }

  Future<void> _persistIndex() async {
    await workspaceStorage.setCollectionsIndex([
      for (final id in collectionSequence)
        (id: id, name: state![id]!.name),
    ]);
  }

  void loadCollection(String collectionId) {
    if (_loadedCollectionIds.contains(collectionId)) {
      return;
    }
    final json = workspaceStorage.getCollection(collectionId);
    final catalogName = collectionId;
    final model = json != null
        ? CollectionModel.fromJson(Map<String, Object?>.from(json))
        : CollectionModel(id: collectionId, name: catalogName);
    final fromIndex = model.requests
        .where((r) => workspaceStorage.requestExistsOnDisk(collectionId, r.id))
        .toList();
    final fromDisk = _requestsFromDisk(collectionId);
    final byId = <String, RequestSummary>{
      for (final r in fromDisk) r.id: r,
    };
    final requests = <RequestSummary>[
      for (final r in fromIndex)
        if (byId.remove(r.id) case final summary?) summary,
      ...byId.values,
    ];
    _loadedCollectionIds.add(collectionId);
    state = {
      ...state!,
      collectionId: model.copyWith(
        name: catalogName,
        requests: requests,
      ),
    };
  }

  /// Re-read a collection from disk (e.g. after LAN sync updated files).
  void reloadCollectionFromDisk(String collectionId) {
    _loadedCollectionIds.remove(collectionId);
    loadCollection(collectionId);
  }

  void reloadAllCollectionsFromDisk() {
    for (final id in collectionSequence) {
      reloadCollectionFromDisk(id);
    }
  }

  List<RequestSummary> _requestsFromDisk(String collectionId) {
    final takenNames = <String>{};
    final result = <RequestSummary>[];
    for (final folderId
        in workspaceStorage.listRequestIdsOnDisk(collectionId)) {
      final model = requestModelFromDiskFolder(
        storage: workspaceStorage,
        collectionId: collectionId,
        folderId: folderId,
        takenDisplayNamesLowercase: takenNames,
      );
      if (model == null) continue;
      takenNames.add(model.name.toLowerCase());
      result.add(RequestSummary.fromRequestModel(model));
    }
    return result;
  }

  void syncRequests(String collectionId, List<RequestSummary> requests) {
    if (state == null || !state!.containsKey(collectionId)) {
      return;
    }
    _loadedCollectionIds.add(collectionId);
    state = {
      ...state!,
      collectionId: state![collectionId]!.copyWith(requests: requests),
    };
  }

  bool _isCollectionIdTaken(String id, {String? excludeId}) {
    final target = id.toLowerCase();
    for (final existing in collectionSequence) {
      if (existing == excludeId) {
        continue;
      }
      if (existing.toLowerCase() == target) {
        return true;
      }
    }
    return false;
  }

  Future<void> addCollection() async {
    var next = state!.length + 1;
    var name = 'Collection $next';
    while (_isCollectionIdTaken(makeCollectionId(name))) {
      next++;
      name = 'Collection $next';
    }
    final id = makeCollectionId(name);
    final model = CollectionModel(id: id, name: name);
    collectionSequence = [...collectionSequence, id];
    _loadedCollectionIds.add(id);
    state = {...state!, id: model};
    await workspaceStorage.setCollection(id, model.toJson());
    await _persistIndex();
    ref.read(expandedCollectionIdsProvider.notifier).update(
          (ids) => {...ids, id},
        );
    await ref
        .read(activeCollectionProvider.notifier)
        .ensureActive(id);
  }

  Future<bool> renameCollection(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        state == null ||
        !state!.containsKey(id) ||
        collectionNameHasIllegalChars(trimmed)) {
      return false;
    }
    final newId = makeCollectionId(trimmed);
    if (newId == id) {
      state = {...state!, id: state![id]!.copyWith(name: trimmed)};
      await _persistIndex();
      return true;
    }
    if (_isCollectionIdTaken(newId, excludeId: id)) {
      return false;
    }

    await workspaceStorage.renameCollection(id, newId);

    final model = CollectionModel(
      id: newId,
      name: trimmed,
      requests: state![id]!.requests,
    );
    final seqIdx = collectionSequence.indexOf(id);
    collectionSequence = [...collectionSequence];
    collectionSequence[seqIdx] = newId;
    _loadedCollectionIds.remove(id);
    _loadedCollectionIds.add(newId);

    state = {...state!}..remove(id);
    state![newId] = model;

    if (ref.read(selectedCollectionIdStateProvider) == id) {
      ref.read(selectedCollectionIdStateProvider.notifier).state = newId;
    }
    ref.read(expandedCollectionIdsProvider.notifier).update((expanded) {
      final next = {...expanded};
      if (next.remove(id)) {
        next.add(newId);
      }
      return next;
    });

    await _persistIndex();
    return true;
  }

  Future<void> _detachCollectionFromMemory(String id) async {
    final wasActive = ref.read(selectedCollectionIdStateProvider) == id;
    collectionSequence = [...collectionSequence]..remove(id);
    _loadedCollectionIds.remove(id);
    state = {...state!}..remove(id);
    ref
        .read(expandedCollectionIdsProvider.notifier)
        .update((s) => {...s}..remove(id));
    await _persistIndex();
    if (wasActive) {
      final nextId =
          collectionSequence.isNotEmpty ? collectionSequence.first : null;
      await ref.read(activeCollectionProvider.notifier).ensureActive(nextId);
    }
  }

  Future<void> deleteCollection(String id) async {
    if (state == null || !state!.containsKey(id)) {
      return;
    }
    await workspaceStorage.deleteCollection(id);
    await _detachCollectionFromMemory(id);
  }

  Future<bool> applyExternalCollectionRemoved(String id) async {
    if (state == null || !state!.containsKey(id)) {
      return false;
    }
    await _detachCollectionFromMemory(id);
    return true;
  }

  Future<bool> applyExternalRequestRemoved(
    String collectionId,
    String requestId,
  ) async {
    if (state == null || !state!.containsKey(collectionId)) {
      return false;
    }
    final activeId = ref.read(selectedCollectionIdStateProvider);
    if (activeId == collectionId) {
      return ref
          .read(activeCollectionProvider.notifier)
          .applyExternalRequestRemoved(requestId);
    }

    final collection = state![collectionId]!;
    if (!collection.requests.any((r) => r.id == requestId)) {
      return false;
    }
    final nextRequests =
        collection.requests.where((r) => r.id != requestId).toList();
    syncRequests(collectionId, nextRequests);
    await _persistRequestIndex(collectionId);
    return true;
  }

  bool applyExternalRequestContentChanged(
    String collectionId,
    String requestId,
  ) {
    if (!workspaceStorage.requestExistsOnDisk(collectionId, requestId)) {
      return false;
    }
    final activeId = ref.read(selectedCollectionIdStateProvider);
    if (activeId == collectionId) {
      return ref
          .read(activeCollectionProvider.notifier)
          .applyExternalRequestContentChanged(requestId);
    }

    if (state == null || !state!.containsKey(collectionId)) {
      return false;
    }
    final model = requestModelFromDiskFolder(
      storage: workspaceStorage,
      collectionId: collectionId,
      folderId: requestId,
    );
    if (model == null) return false;
    final summary = RequestSummary.fromRequestModel(model);
    final collection = state![collectionId]!;
    if (!collection.requests.any((r) => r.id == requestId)) {
      return applyExternalRequestAdded(collectionId, requestId);
    }
    syncRequests(collectionId, [
      for (final r in collection.requests)
        if (r.id == requestId) summary else r,
    ]);
    return true;
  }

  Future<bool> applyExternalCollectionAdded(String collectionId) async {
    if (state == null || state!.containsKey(collectionId)) {
      return false;
    }
    final collectionDir = Directory(
      p.join(
        workspaceStorage.rootPath,
        kWorkspaceCollectionsDir,
        collectionId,
      ),
    );
    if (!await collectionDir.exists()) {
      return false;
    }

    final model = CollectionModel(id: collectionId, name: collectionId);
    collectionSequence = [...collectionSequence, collectionId];
    state = {...state!, collectionId: model};
    loadCollection(collectionId);
    await _persistIndex();
    final loaded = state![collectionId]!;
    await workspaceStorage.setCollection(collectionId, loaded.toJson());
    return true;
  }

  bool applyExternalRequestAdded(String collectionId, String requestId) {
    if (!workspaceStorage.requestExistsOnDisk(collectionId, requestId)) {
      return false;
    }
    final activeId = ref.read(selectedCollectionIdStateProvider);
    if (activeId == collectionId) {
      return ref
          .read(activeCollectionProvider.notifier)
          .applyExternalRequestAdded(requestId);
    }

    if (state == null || !state!.containsKey(collectionId)) {
      return false;
    }

    loadCollection(collectionId);
    final loaded = state![collectionId]!;
    if (loaded.requests.any((r) => r.id == requestId)) {
      return false;
    }

    final takenNames = <String>{
      for (final r in loaded.requests) r.name.toLowerCase(),
    };
    final takenIds = loaded.requests.map((r) => r.id).toSet();
    final adopted = adoptRequestFolderFromDisk(
      storage: workspaceStorage,
      collectionId: collectionId,
      folderId: requestId,
      takenNamesLower: takenNames,
      takenIds: takenIds,
    );
    if (adopted == null ||
        loaded.requests.any((r) => r.id == adopted.id)) {
      return false;
    }

    final summary = RequestSummary.fromRequestModel(adopted.model);
    syncRequests(collectionId, [...loaded.requests, summary]);
    unawaited(() async {
      final settings = ref.read(settingsProvider);
      var payload = settings.saveResponses
          ? adopted.model.toJson()
          : adopted.model.copyWith(httpResponseModel: null).toJson();
      payload = AiRequestSecretsStorage.stripApiKeyFromJson(
        Map<String, dynamic>.from(payload),
      );
      await workspaceStorage.setRequestModel(
        collectionId,
        adopted.id,
        payload,
        saveMediaAsFiles: settings.saveMediaResponsesAsFiles,
      );
      await _persistRequestIndex(collectionId);
    }());
    return true;
  }

  Future<bool> applyExternalCollectionIndexChanged() async {
    if (state == null) return false;
    final index = workspaceStorage.getCollectionsIndex();
    final diskIds = <String>{
      for (final entry in index) entry.id,
    };

    final collectionsDir = Directory(
      p.join(workspaceStorage.rootPath, kWorkspaceCollectionsDir),
    );
    if (await collectionsDir.exists()) {
      await for (final entity in collectionsDir.list()) {
        if (entity is! Directory) continue;
        final id = p.basename(entity.path);
        if (id.startsWith('.') || id == kWorkspaceCollectionsIndexFile) {
          continue;
        }
        diskIds.add(id);
      }
    }

    var changed = false;
    final ordered = <String>[
      for (final entry in index) entry.id,
      for (final id in diskIds)
        if (!index.any((e) => e.id == id)) id,
    ];

    for (final id in ordered) {
      if (!state!.containsKey(id)) {
        final added = await applyExternalCollectionAdded(id);
        changed = changed || added;
      }
    }

    if (!listEquals(collectionSequence, ordered)) {
      collectionSequence = ordered;
      state = {...state!};
      changed = true;
    }

    if (changed) {
      await _persistIndex();
    }
    return changed;
  }

  bool applyExternalRequestIndexChanged(String collectionId) {
    final activeId = ref.read(selectedCollectionIdStateProvider);
    if (activeId == collectionId) {
      return ref
          .read(activeCollectionProvider.notifier)
          .applyExternalRequestIndexChanged();
    }
    if (state == null || !state!.containsKey(collectionId)) {
      return false;
    }
    _loadedCollectionIds.remove(collectionId);
    loadCollection(collectionId);
    return true;
  }

  Future<void> _persistRequestIndex(String collectionId) async {
    final model = state?[collectionId];
    if (model == null) return;
    await workspaceStorage.setCollection(collectionId, model.toJson());
  }

  Future<void> saveCollections() async {
    await _persistIndex();
    final activeId = ref.read(selectedCollectionIdStateProvider);
    var activeSequence = ref.read(requestSequenceProvider);
    if (activeId != null &&
        activeSequence.isEmpty &&
        workspaceStorage.listRequestIdsOnDisk(activeId).isNotEmpty) {
      activeSequence = workspaceStorage.getKnownRequestIds(activeId);
    }
    final collectionNotifier =
        ref.read(activeCollectionProvider.notifier);
    for (final entry in state!.entries) {
      if (!_loadedCollectionIds.contains(entry.key)) {
        continue;
      }

      final requests = entry.key == activeId
          ? collectionNotifier.summariesForSequence(entry.key, activeSequence)
          : entry.value.requests.isNotEmpty
              ? entry.value.requests
                  .where((r) =>
                      workspaceStorage.requestExistsOnDisk(entry.key, r.id))
                  .toList()
              : _requestsFromDisk(entry.key);
      if (entry.key == activeId) {
        syncRequests(entry.key, requests);
      }
      final model = entry.value.copyWith(requests: requests);
      await workspaceStorage.setCollection(entry.key, model.toJson());
      if (entry.key != activeId) {
        state = {...state!, entry.key: model};
      }
    }
  }
}
