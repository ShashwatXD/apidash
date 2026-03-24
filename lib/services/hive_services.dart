import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

enum HiveBoxType { normal, lazy }

const String kDataBox = "apidash-data";
const String kKeyDataBoxIds = "ids";
const String kKeyCollectionIds = "collectionIds";
const String kKeyActiveCollectionId = "activeCollectionId";
const String kCollectionMetaPrefix = "collection_meta_";
const String kCollectionRequestIdsPrefix = "collection_req_ids_";
const String kCollectionRequestPrefix = "collection_req_";
const String kWorkflowIds = "workflow_ids";
const String kActiveWorkflowId = "active_workflow_id";
const String kWorkflowPrefix = "workflow_";
const String kWorkflowRunHistoryPrefix = "workflow_runs_";

const String kEnvironmentBox = "apidash-environments";
const String kKeyEnvironmentBoxIds = "environmentIds";

const String kHistoryMetaBox = "apidash-history-meta";
const String kHistoryBoxIds = "historyIds";
const String kHistoryLazyBox = "apidash-history-lazy";

const String kDashBotBox = "apidash-dashbot-data";
const String kKeyDashBotBoxIds = 'messages';

const kHiveBoxes = [
  (kDataBox, HiveBoxType.normal),
  (kEnvironmentBox, HiveBoxType.normal),
  (kHistoryMetaBox, HiveBoxType.normal),
  (kHistoryLazyBox, HiveBoxType.lazy),
  (kDashBotBox, HiveBoxType.lazy),
];

Future<bool> initHiveBoxes(
  bool initializeUsingPath,
  String? workspaceFolderPath,
) async {
  try {
    if (initializeUsingPath) {
      if (workspaceFolderPath != null) {
        Hive.init(workspaceFolderPath);
      } else {
        return false;
      }
    } else {
      await Hive.initFlutter();
    }
    final openHiveBoxesStatus = await openHiveBoxes();
    return openHiveBoxesStatus;
  } catch (e) {
    return false;
  }
}

Future<bool> openHiveBoxes() async {
  try {
    for (var box in kHiveBoxes) {
      if (box.$2 == HiveBoxType.normal) {
        await Hive.openBox(box.$1);
      } else if (box.$2 == HiveBoxType.lazy) {
        await Hive.openLazyBox(box.$1);
      }
    }
    return true;
  } catch (e) {
    debugPrint("ERROR OPEN HIVE BOXES: $e");
    return false;
  }
}

Future<void> clearHiveBoxes() async {
  try {
    for (var box in kHiveBoxes) {
      if (Hive.isBoxOpen(box.$1)) {
        if (box.$2 == HiveBoxType.normal) {
          await Hive.box(box.$1).clear();
        } else if (box.$2 == HiveBoxType.lazy) {
          await Hive.lazyBox(box.$1).clear();
        }
      }
    }
  } catch (e) {
    debugPrint("ERROR CLEAR HIVE BOXES: $e");
  }
}

Future<void> deleteHiveBoxes() async {
  try {
    for (var box in kHiveBoxes) {
      if (Hive.isBoxOpen(box.$1)) {
        if (box.$2 == HiveBoxType.normal) {
          await Hive.box(box.$1).deleteFromDisk();
        } else if (box.$2 == HiveBoxType.lazy) {
          await Hive.lazyBox(box.$1).deleteFromDisk();
        }
      }
    }
    await Hive.close();
  } catch (e) {
    debugPrint("ERROR DELETE HIVE BOXES: $e");
  }
}

final hiveHandler = HiveHandler();

class HiveHandler {
  late final Box dataBox;
  late final Box environmentBox;
  late final Box historyMetaBox;
  late final LazyBox historyLazyBox;
  late final LazyBox dashBotBox;

  HiveHandler() {
    debugPrint("Trying to open Hive boxes");
    dataBox = Hive.box(kDataBox);
    environmentBox = Hive.box(kEnvironmentBox);
    historyMetaBox = Hive.box(kHistoryMetaBox);
    historyLazyBox = Hive.lazyBox(kHistoryLazyBox);
    dashBotBox = Hive.lazyBox(kDashBotBox);
  }

  dynamic getIds() => dataBox.get(kKeyDataBoxIds);
  Future<void> setIds(List<String>? ids) => dataBox.put(kKeyDataBoxIds, ids);

  dynamic getRequestModel(String id) => dataBox.get(id);
  Future<void> setRequestModel(
          String id, Map<String, dynamic>? requestModelJson) =>
      dataBox.put(id, requestModelJson);

  dynamic getCollectionIds() => dataBox.get(kKeyCollectionIds);
  Future<void> setCollectionIds(List<String>? ids) =>
      dataBox.put(kKeyCollectionIds, ids);

  String? getActiveCollectionId() => dataBox.get(kKeyActiveCollectionId);
  Future<void> setActiveCollectionId(String? collectionId) =>
      dataBox.put(kKeyActiveCollectionId, collectionId);

  dynamic getCollectionMeta(String collectionId) =>
      dataBox.get('$kCollectionMetaPrefix$collectionId');
  Future<void> setCollectionMeta(
    String collectionId,
    Map<String, dynamic>? collectionMetaJson,
  ) =>
      dataBox.put('$kCollectionMetaPrefix$collectionId', collectionMetaJson);

  dynamic getCollectionRequestIds(String collectionId) =>
      dataBox.get('$kCollectionRequestIdsPrefix$collectionId');
  Future<void> setCollectionRequestIds(
    String collectionId,
    List<String>? ids,
  ) =>
      dataBox.put('$kCollectionRequestIdsPrefix$collectionId', ids);

  dynamic getCollectionRequestModel(String collectionId, String requestId) =>
      dataBox.get('$kCollectionRequestPrefix${collectionId}_$requestId');
  Future<void> setCollectionRequestModel(
    String collectionId,
    String requestId,
    Map<String, dynamic>? requestModelJson,
  ) =>
      dataBox.put(
        '$kCollectionRequestPrefix${collectionId}_$requestId',
        requestModelJson,
      );

  dynamic getWorkflowIds() => dataBox.get(kWorkflowIds);
  Future<void> setWorkflowIds(List<String>? ids) => dataBox.put(kWorkflowIds, ids);

  String? getActiveWorkflowId() => dataBox.get(kActiveWorkflowId);
  Future<void> setActiveWorkflowId(String? workflowId) =>
      dataBox.put(kActiveWorkflowId, workflowId);

  dynamic getWorkflow(String workflowId) => dataBox.get('$kWorkflowPrefix$workflowId');
  Future<void> setWorkflow(String workflowId, Map<String, dynamic>? workflowJson) =>
      dataBox.put('$kWorkflowPrefix$workflowId', workflowJson);

  dynamic getWorkflowRunHistory(String workflowId) =>
      dataBox.get('$kWorkflowRunHistoryPrefix$workflowId');
  Future<void> setWorkflowRunHistory(
    String workflowId,
    List<Map<String, dynamic>>? runsJson,
  ) =>
      dataBox.put('$kWorkflowRunHistoryPrefix$workflowId', runsJson);

  Future<void> deleteWorkflow(String workflowId) async {
    await dataBox.delete('$kWorkflowPrefix$workflowId');
    await dataBox.delete('$kWorkflowRunHistoryPrefix$workflowId');
  }

  Future<void> deleteCollection(String collectionId) async {
    final ids = (getCollectionRequestIds(collectionId) as List?) ?? [];
    for (final requestId in ids.whereType<String>()) {
      await dataBox.delete('$kCollectionRequestPrefix${collectionId}_$requestId');
    }
    await dataBox.delete('$kCollectionRequestIdsPrefix$collectionId');
    await dataBox.delete('$kCollectionMetaPrefix$collectionId');
  }

  void delete(String key) => dataBox.delete(key);

  dynamic getEnvironmentIds() => environmentBox.get(kKeyEnvironmentBoxIds);
  Future<void> setEnvironmentIds(List<String>? ids) =>
      environmentBox.put(kKeyEnvironmentBoxIds, ids);

  dynamic getEnvironment(String id) => environmentBox.get(id);
  Future<void> setEnvironment(
          String id, Map<String, dynamic>? environmentJson) =>
      environmentBox.put(id, environmentJson);

  Future<void> deleteEnvironment(String id) => environmentBox.delete(id);

  dynamic getHistoryIds() => historyMetaBox.get(kHistoryBoxIds);
  Future<void> setHistoryIds(List<String>? ids) =>
      historyMetaBox.put(kHistoryBoxIds, ids);

  dynamic getHistoryMeta(String id) => historyMetaBox.get(id);
  Future<void> setHistoryMeta(
          String id, Map<String, dynamic>? historyMetaJson) =>
      historyMetaBox.put(id, historyMetaJson);

  Future<void> deleteHistoryMeta(String id) => historyMetaBox.delete(id);

  Future<dynamic> getHistoryRequest(String id) async =>
      await historyLazyBox.get(id);
  Future<void> setHistoryRequest(
          String id, Map<String, dynamic>? historyRequestJson) =>
      historyLazyBox.put(id, historyRequestJson);

  Future<void> deleteHistoryRequest(String id) => historyLazyBox.delete(id);

  Future<dynamic> getDashbotMessages() async =>
      await dashBotBox.get(kKeyDashBotBoxIds);
  Future<void> saveDashbotMessages(String messages) =>
      dashBotBox.put(kKeyDashBotBoxIds, messages);

  Future clearAllHistory() async {
    await historyMetaBox.clear();
    await historyLazyBox.clear();
  }

  Future clear() async {
    await dataBox.clear();
    await environmentBox.clear();
    await historyMetaBox.clear();
    await historyLazyBox.clear();
    await dashBotBox.clear();
  }

  Future<void> removeUnused() async {
    var ids = getIds();
    final collectionIds = getCollectionIds();
    final hasCollections = collectionIds is List && collectionIds.isNotEmpty;
    if (ids != null && !hasCollections) {
      ids = ids as List;
      for (var key in dataBox.keys.toList()) {
        if (key != kKeyDataBoxIds && !ids.contains(key)) {
          await dataBox.delete(key);
        }
      }
    }
    if (hasCollections) {
      final cIds = collectionIds.cast<String>();
      final validKeys = <String>{
        kKeyCollectionIds,
        kKeyActiveCollectionId,
        kKeyDataBoxIds,
        kWorkflowIds,
        kActiveWorkflowId,
      };
      final workflowIds = (getWorkflowIds() as List?) ?? [];
      for (final workflowId in workflowIds.whereType<String>()) {
        validKeys.add('$kWorkflowPrefix$workflowId');
        validKeys.add('$kWorkflowRunHistoryPrefix$workflowId');
      }
      for (final cId in cIds) {
        validKeys.add('$kCollectionMetaPrefix$cId');
        validKeys.add('$kCollectionRequestIdsPrefix$cId');
        final requestIds = (getCollectionRequestIds(cId) as List?) ?? [];
        for (final requestId in requestIds.whereType<String>()) {
          validKeys.add('$kCollectionRequestPrefix${cId}_$requestId');
        }
      }
      for (final key in dataBox.keys.toList()) {
        if (key is String && key.startsWith(kCollectionRequestPrefix)) {
          if (!validKeys.contains(key)) {
            await dataBox.delete(key);
          }
          continue;
        }
        if (key is String &&
            (key.startsWith(kCollectionMetaPrefix) ||
                key.startsWith(kCollectionRequestIdsPrefix))) {
          if (!validKeys.contains(key)) {
            await dataBox.delete(key);
          }
          continue;
        }
        if (key is String &&
            (key.startsWith(kWorkflowPrefix) ||
                key.startsWith(kWorkflowRunHistoryPrefix))) {
          if (!validKeys.contains(key)) {
            await dataBox.delete(key);
          }
          continue;
        }
      }
    }
    var environmentIds = getEnvironmentIds();
    if (environmentIds != null) {
      environmentIds = environmentIds as List;
      for (var key in environmentBox.keys.toList()) {
        if (key != kKeyEnvironmentBoxIds && !environmentIds.contains(key)) {
          await environmentBox.delete(key);
        }
      }
    }
  }
}
