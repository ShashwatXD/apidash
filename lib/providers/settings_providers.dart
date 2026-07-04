import 'package:apidash_core/apidash_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../services/services.dart';
import '../consts.dart';

final codegenLanguageProvider = Provider<CodegenLanguage>((ref) {
  return ref.watch(
    settingsProvider.select((value) => value.defaultCodeGenLang),
  );
});

final activeEnvironmentIdProvider = Provider<String?>((ref) {
  return ref.watch(
    settingsProvider.select((value) => value.activeEnvironmentId),
  );
});

final StateNotifierProvider<ThemeStateNotifier, SettingsModel>
settingsProvider = StateNotifierProvider((ref) => ThemeStateNotifier());

class ThemeStateNotifier extends StateNotifier<SettingsModel> {
  ThemeStateNotifier({this.settingsModel}) : super(const SettingsModel()) {
    state = settingsModel ?? const SettingsModel();
    _backfillWorkspaceListIfNeeded();
  }
  final SettingsModel? settingsModel;

  void _backfillWorkspaceListIfNeeded() {
    final path = state.workspaceFolderPath;
    if (path == null || path.isEmpty || state.savedWorkspaces.isNotEmpty) {
      return;
    }
    Future.microtask(() async {
      await rememberWorkspace(path: path, name: p.basename(path));
    });
  }

  Future<void> update({
    bool? isDark,
    bool? alwaysShowCollectionPaneScrollbar,
    Size? size,
    Offset? offset,
    SupportedUriSchemes? defaultUriScheme,
    CodegenLanguage? defaultCodeGenLang,
    bool? saveResponses,
    bool? saveMediaResponsesAsFiles,
    bool? promptBeforeClosing,
    String? activeEnvironmentId,
    HistoryRetentionPeriod? historyRetentionPeriod,
    String? workspaceFolderPath,
    List<SavedWorkspaceEntry>? savedWorkspaces,
    bool? isSSLDisabled,
    bool? isDashBotEnabled,
    Map<String, Object?>? defaultAIModel,
  }) async {
    state = state.copyWith(
      isDark: isDark,
      alwaysShowCollectionPaneScrollbar: alwaysShowCollectionPaneScrollbar,
      size: size,
      offset: offset,
      defaultUriScheme: defaultUriScheme,
      defaultCodeGenLang: defaultCodeGenLang,
      saveResponses: saveResponses,
      saveMediaResponsesAsFiles: saveMediaResponsesAsFiles,
      promptBeforeClosing: promptBeforeClosing,
      activeEnvironmentId: activeEnvironmentId,
      historyRetentionPeriod: historyRetentionPeriod,
      workspaceFolderPath: workspaceFolderPath,
      savedWorkspaces: savedWorkspaces,
      isSSLDisabled: isSSLDisabled,
      isDashBotEnabled: isDashBotEnabled,
      defaultAIModel: defaultAIModel,
    );
    await setSettingsToSharedPrefs(state);
  }

  Future<void> clearActiveWorkspace({bool removeFromRecents = false}) async {
    final path = state.workspaceFolderPath;
    final savedWorkspaces = removeFromRecents &&
            path != null &&
            path.isNotEmpty
        ? state.savedWorkspaces
            .where((e) => p.normalize(e.path) != p.normalize(path))
            .toList()
        : state.savedWorkspaces;
    state = state.copyWithPath(workspaceFolderPath: null).copyWith(
      savedWorkspaces: savedWorkspaces,
    );
    await setSettingsToSharedPrefs(state);
  }

  Future<void> rememberWorkspace({
    required String path,
    required String name,
  }) async {
    final normalized = p.normalize(path);
    final rest = state.savedWorkspaces
        .where((e) => p.normalize(e.path) != normalized)
        .toList();
    final list = [
      SavedWorkspaceEntry(path: normalized, name: name),
      ...rest,
    ].take(kMaxSavedWorkspaces).toList();
    await update(
      workspaceFolderPath: normalized,
      savedWorkspaces: list,
    );
  }

  Future<void> renameWorkspace({
    required String path,
    required String name,
  }) async {
    final normalized = p.normalize(path);
    final list = state.savedWorkspaces
        .map(
          (e) => p.normalize(e.path) == normalized
              ? SavedWorkspaceEntry(path: e.path, name: name)
              : e,
        )
        .toList();
    await update(savedWorkspaces: list);
  }

  Future<void> forgetWorkspace(String path) async {
    final normalized = p.normalize(path);
    final list = state.savedWorkspaces
        .where((e) => p.normalize(e.path) != normalized)
        .toList();
    await update(savedWorkspaces: list);
  }
}

String? savedWorkspaceNameForPath(
  List<SavedWorkspaceEntry> saved,
  String? workspaceFolderPath,
) {
  if (workspaceFolderPath == null || workspaceFolderPath.isEmpty) {
    return null;
  }
  final normalized = p.normalize(workspaceFolderPath);
  for (final entry in saved) {
    if (p.normalize(entry.path) == normalized) {
      return entry.name;
    }
  }
  return null;
}
