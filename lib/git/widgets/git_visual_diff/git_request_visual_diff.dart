import 'package:apidash/consts.dart';
import 'package:apidash/models/request_model.dart';
import 'package:apidash/utils/utils.dart';
import 'package:apidash/widgets/widgets.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

import 'git_diff_chrome.dart';
import 'git_diff_side_by_side_shell.dart';
import 'git_json_fallback_column.dart';

RequestModel? parseRequestModel(Map<String, Object?>? json) {
  if (json == null) return null;
  try {
    var requestModel = RequestModel.fromJson(json);
    if (requestModel.httpRequestModel == null &&
        requestModel.aiRequestModel == null) {
      requestModel = requestModel.copyWith(
        httpRequestModel: const HttpRequestModel(),
      );
    }
    return requestModel;
  } catch (_) {
    return null;
  }
}

List<GitDiffChangedField> collectRequestDiffChanges({
  required RequestModel? original,
  required RequestModel? current,
}) {
  if (original == null && current == null) return const [];

  final changes = <GitDiffChangedField>[];
  void add(
    String label,
    Object? a,
    Object? b, {
    String? Function(Object? a, Object? b)? detailOf,
  }) {
    final kind = _pairChangeKind(a, b);
    if (kind == null) return;
    changes.add(
      GitDiffChangedField(
        label: label,
        kind: kind,
        detail: detailOf?.call(a, b),
      ),
    );
  }

  add(
    'Name',
    original?.name,
    current?.name,
    detailOf: (a, b) => '${_preview(a)} → ${_preview(b)}',
  );
  add(
    'Description',
    original?.description,
    current?.description,
  );
  add(
    'Type',
    original?.apiType,
    current?.apiType,
    detailOf: (a, b) =>
        '${(a as APIType?)?.label ?? '—'} → ${(b as APIType?)?.label ?? '—'}',
  );

  final oh = original?.httpRequestModel;
  final ch = current?.httpRequestModel;
  add(
    'Method',
    oh?.method,
    ch?.method,
    detailOf: (a, b) =>
        '${(a as HTTPVerb?)?.name.toUpperCase() ?? '—'} → '
        '${(b as HTTPVerb?)?.name.toUpperCase() ?? '—'}',
  );
  add(
    'URL',
    oh?.url,
    ch?.url,
    detailOf: (a, b) => '${_preview(a)} → ${_preview(b)}',
  );
  add(
    'Auth',
    _configuredAuthType(oh),
    _configuredAuthType(ch),
    detailOf: (a, b) =>
        '${(a as APIAuthType?)?.displayType ?? 'None'} → '
        '${(b as APIAuthType?)?.displayType ?? 'None'}',
  );
  add(
    'Headers',
    oh?.headersMap,
    ch?.headersMap,
    detailOf: (a, b) =>
        '${_mapCount(a)} → ${_mapCount(b)}',
  );
  add(
    'URL Params',
    oh?.paramsMap,
    ch?.paramsMap,
    detailOf: (a, b) => '${_mapCount(a)} → ${_mapCount(b)}',
  );
  add(
    'Body',
    oh == null ? null : _requestBodySignature(oh),
    ch == null ? null : _requestBodySignature(ch),
    detailOf: (_, _) {
      final from = oh?.bodyContentType.name ?? '—';
      final to = ch?.bodyContentType.name ?? '—';
      return from == to ? from : '$from → $to';
    },
  );
  add('GraphQL Query', oh?.query, ch?.query);
  add(
    'Pre-request Script',
    original?.preRequestScript,
    current?.preRequestScript,
  );
  add(
    'Post-response Script',
    original?.postRequestScript,
    current?.postRequestScript,
  );

  final oa = original?.aiRequestModel;
  final ca = current?.aiRequestModel;
  add('AI Provider', oa?.modelApiProvider?.name, ca?.modelApiProvider?.name);
  add('AI Model', oa?.model, ca?.model);
  add('AI URL', oa?.url, ca?.url);
  add('System Prompt', oa?.systemPrompt, ca?.systemPrompt);
  add('User Prompt', oa?.userPrompt, ca?.userPrompt);

  return changes;
}

String _preview(Object? value) {
  final text = (value?.toString() ?? '').trim();
  if (text.isEmpty) return '—';
  if (text.length <= 42) return text;
  return '${text.substring(0, 39)}…';
}

String _mapCount(Object? value) {
  if (value is Map) return '${value.length}';
  return '0';
}

GitDiffChangeKind? _pairChangeKind(Object? a, Object? b) {
  if (_diffValueEquals(a, b)) return null;
  final hasA = _hasDiffValue(a);
  final hasB = _hasDiffValue(b);
  if (!hasA && !hasB) return null;
  if (!hasA && hasB) return GitDiffChangeKind.added;
  if (hasA && !hasB) return GitDiffChangeKind.removed;
  return GitDiffChangeKind.modified;
}

class GitRequestVisualDiff extends StatelessWidget {
  const GitRequestVisualDiff({
    super.key,
    required this.original,
    required this.current,
    this.originalRaw,
    this.currentRaw,
  });

  final RequestModel? original;
  final RequestModel? current;
  final String? originalRaw;
  final String? currentRaw;

  @override
  Widget build(BuildContext context) {
    final changes = collectRequestDiffChanges(
      original: original,
      current: current,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GitDiffChangeSummaryBar(changes: changes),
        Expanded(
          child: GitDiffSideBySideShell(
            original: _RequestDiffColumn(
              model: original,
              otherModel: current,
              side: _DiffSide.original,
              raw: originalRaw,
              fieldKey: 'git-diff-request-original',
            ),
            current: _RequestDiffColumn(
              model: current,
              otherModel: original,
              side: _DiffSide.current,
              raw: currentRaw,
              fieldKey: 'git-diff-request-current',
            ),
          ),
        ),
      ],
    );
  }
}

enum _DiffSide { original, current }

class _RequestDiffSlots {
  const _RequestDiffSlots({
    required this.showName,
    required this.showDescription,
    required this.showType,
    required this.showRestLine,
    required this.showAi,
    required this.showAuth,
    required this.showHeaders,
    required this.showParams,
    required this.showBody,
    required this.showGraphqlQuery,
    required this.showPreScript,
    required this.showPostScript,
  });

  final bool showName;
  final bool showDescription;
  final bool showType;
  final bool showRestLine;
  final bool showAi;
  final bool showAuth;
  final bool showHeaders;
  final bool showParams;
  final bool showBody;
  final bool showGraphqlQuery;
  final bool showPreScript;
  final bool showPostScript;

  factory _RequestDiffSlots.compare(
    RequestModel? model,
    RequestModel? otherModel,
  ) {
    final http = model?.httpRequestModel;
    final otherHttp = otherModel?.httpRequestModel;
    final effectiveApiType = model?.apiType ?? otherModel?.apiType;

    return _RequestDiffSlots(
      showName: _hasDiffValue(model?.name) || _hasDiffValue(otherModel?.name),
      showDescription:
          _hasDiffValue(model?.description) ||
          _hasDiffValue(otherModel?.description),
      showType: model != null || otherModel != null,
      showRestLine:
          effectiveApiType == APIType.rest &&
          (http != null || otherHttp != null),
      showAi:
          effectiveApiType == APIType.ai &&
          (model?.aiRequestModel != null || otherModel?.aiRequestModel != null),
      showAuth: _hasConfiguredAuth(http) || _hasConfiguredAuth(otherHttp),
      showHeaders:
          (http?.headersMap.isNotEmpty ?? false) ||
          (otherHttp?.headersMap.isNotEmpty ?? false),
      showParams:
          (http?.paramsMap.isNotEmpty ?? false) ||
          (otherHttp?.paramsMap.isNotEmpty ?? false),
      showBody:
          effectiveApiType == APIType.rest &&
          ((http?.hasBody ?? false) || (otherHttp?.hasBody ?? false)),
      showGraphqlQuery:
          effectiveApiType == APIType.graphql &&
          ((http?.query?.trim().isNotEmpty ?? false) ||
              (otherHttp?.query?.trim().isNotEmpty ?? false)),
      showPreScript:
          (model?.preRequestScript?.trim().isNotEmpty ?? false) ||
          (otherModel?.preRequestScript?.trim().isNotEmpty ?? false),
      showPostScript:
          (model?.postRequestScript?.trim().isNotEmpty ?? false) ||
          (otherModel?.postRequestScript?.trim().isNotEmpty ?? false),
    );
  }
}

class _RequestDiffColumn extends StatelessWidget {
  const _RequestDiffColumn({
    required this.model,
    required this.otherModel,
    required this.side,
    required this.raw,
    required this.fieldKey,
  });

  final RequestModel? model;
  final RequestModel? otherModel;
  final _DiffSide side;
  final String? raw;
  final String fieldKey;

  @override
  Widget build(BuildContext context) {
    if (model == null) {
      if (raw != null && raw!.trim().isNotEmpty) {
        return GitJsonFallbackColumn(raw: raw, fieldKey: fieldKey);
      }
      if (otherModel != null) {
        return _RequestNoContentColumn(
          referenceModel: otherModel!,
          slots: _RequestDiffSlots.compare(null, otherModel),
        );
      }
      return const GitDiffEmptyState();
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final http = model!.httpRequestModel;
    final otherHttp = otherModel?.httpRequestModel;
    final apiType = model!.apiType;
    final slots = _RequestDiffSlots.compare(model, otherModel);

    Widget section(
      String label,
      Widget child, {
      GitDiffChangeKind? change,
      String? subtitle,
      Widget? trailing,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GitDiffSectionHeader(
            label: label,
            change: change,
            subtitle: subtitle,
            trailing: trailing,
          ),
          _GitDiffChangedBox(change: change, child: child),
          kVSpacer10,
        ],
      );
    }

    return SingleChildScrollView(
      padding: kP12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (slots.showName)
            section(
              'Name',
              model!.name.trim().isEmpty
                  ? const _GitDiffNoContentBox()
                  : Text(
                      model!.name,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
              change: _fieldChangeKind(model!.name, otherModel?.name, side),
            ),
          if (slots.showDescription)
            section(
              'Description',
              model!.description.trim().isEmpty
                  ? const _GitDiffNoContentBox()
                  : Text(
                      model!.description,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              change: _fieldChangeKind(
                model!.description,
                otherModel?.description,
                side,
              ),
            ),
          if (slots.showType)
            section(
              'Type',
              Text(
                apiType.label,
                style: kCodeStyle.copyWith(fontWeight: FontWeight.w600),
              ),
              change: _fieldChangeKind(apiType, otherModel?.apiType, side),
            ),
          if (slots.showRestLine) ...[
            if (apiType == APIType.rest && http != null) ...[
              section(
                'Method',
                Text(
                  http.method.name.toUpperCase(),
                  style: kCodeStyle.copyWith(
                    fontWeight: FontWeight.bold,
                    color: getAPIColor(
                      apiType,
                      method: http.method,
                      brightness: Theme.of(context).brightness,
                    ),
                  ),
                ),
                change: _fieldChangeKind(
                  http.method,
                  otherHttp?.method,
                  side,
                ),
              ),
              section(
                'URL',
                ReadOnlyTextField(
                  initialValue: http.url,
                  style: kCodeStyle,
                ),
                change: _fieldChangeKind(http.url, otherHttp?.url, side),
              ),
            ] else ...[
              section('Method', const _GitDiffNoContentBox()),
              section('URL', const _GitDiffNoContentBox()),
            ],
          ],
          if (slots.showAi) ...[
            apiType == APIType.ai && model!.aiRequestModel != null
                ? _AiRequestDiffBody(
                  ai: model!.aiRequestModel!,
                  otherAi: otherModel?.aiRequestModel,
                  side: side,
                  idSuffix: model!.id,
                )
                : _AiRequestNoContentBody(ai: otherModel!.aiRequestModel!),
          ],
          if (slots.showAuth)
            section(
              kLabelAuthorization,
              _hasConfiguredAuth(http)
                  ? Text(
                      http!.authModel!.type.displayType,
                      style: kCodeStyle.copyWith(fontWeight: FontWeight.w600),
                    )
                  : const _GitDiffNoContentBox(),
              change: _fieldChangeKind(
                _configuredAuthType(http),
                _configuredAuthType(otherHttp),
                side,
              ),
              subtitle: _hasConfiguredAuth(http)
                  ? 'Auth type for this request'
                  : null,
            ),
          if (slots.showHeaders)
            section(
              kLabelHeaders,
              http == null || http.headersMap.isEmpty
                  ? const _GitDiffNoContentBox()
                  : _GitDiffKeyValueList(
                    rows: http.headersMap,
                    otherRows: otherHttp?.headersMap ?? const {},
                    side: side,
                  ),
              change: _fieldChangeKind(
                http?.headersMap,
                otherHttp?.headersMap,
                side,
              ),
              subtitle:
                  '${http?.headersMap.length ?? 0} header'
                  '${(http?.headersMap.length ?? 0) == 1 ? '' : 's'}',
            ),
          if (slots.showParams)
            section(
              kLabelURLParams,
              http == null || http.paramsMap.isEmpty
                  ? const _GitDiffNoContentBox()
                  : _GitDiffKeyValueList(
                    rows: http.paramsMap,
                    otherRows: otherHttp?.paramsMap ?? const {},
                    side: side,
                  ),
              change: _fieldChangeKind(
                http?.paramsMap,
                otherHttp?.paramsMap,
                side,
              ),
              subtitle:
                  '${http?.paramsMap.length ?? 0} param'
                  '${(http?.paramsMap.length ?? 0) == 1 ? '' : 's'}',
            ),
          if (slots.showBody)
            section(
              kLabelBody,
              http == null || !http.hasBody
                  ? const _GitDiffNoContentBox(minHeight: 160)
                  : SizedBox(
                    height: 160,
                    child: switch (http.bodyContentType) {
                      ContentType.json => JsonTextFieldEditor(
                        fieldKey: _fieldEditorKey('json', model!.id, side),
                        initialValue: http.body,
                        readOnly: true,
                        isDark: Theme.of(context).brightness == Brightness.dark,
                      ),
                      ContentType.formdata => _GitDiffFormDataList(
                        rows: http.formData ?? [],
                        otherRows: otherHttp?.formData ?? const [],
                        side: side,
                      ),
                      _ => TextFieldEditor(
                        fieldKey: _fieldEditorKey('body', model!.id, side),
                        initialValue: http.body,
                        readOnly: true,
                      ),
                    },
                  ),
              change: _fieldChangeKind(
                http == null ? null : _requestBodySignature(http),
                otherHttp == null ? null : _requestBodySignature(otherHttp),
                side,
              ),
              subtitle: http == null
                  ? null
                  : 'Content type: ${http.bodyContentType.name}',
            ),
          if (slots.showGraphqlQuery)
            section(
              kLabelQuery,
              http == null || (http.query?.trim().isEmpty ?? true)
                  ? const _GitDiffNoContentBox(minHeight: 160)
                  : SizedBox(
                    height: 160,
                    child: TextFieldEditor(
                      fieldKey: _fieldEditorKey('query', model!.id, side),
                      initialValue: http.query,
                      readOnly: true,
                    ),
                  ),
              change: _fieldChangeKind(http?.query, otherHttp?.query, side),
            ),
          if (slots.showPreScript)
            section(
              kLabelPreRequest,
              model!.preRequestScript?.trim().isEmpty ?? true
                  ? const _GitDiffNoContentBox(minHeight: 120)
                  : SizedBox(
                    height: 120,
                    child: TextFieldEditor(
                      fieldKey: _fieldEditorKey('pre', model!.id, side),
                      initialValue: model!.preRequestScript,
                      readOnly: true,
                    ),
                  ),
              change: _fieldChangeKind(
                model!.preRequestScript,
                otherModel?.preRequestScript,
                side,
              ),
            ),
          if (slots.showPostScript)
            section(
              kLabelPostResponse,
              model!.postRequestScript?.trim().isEmpty ?? true
                  ? const _GitDiffNoContentBox(minHeight: 120)
                  : SizedBox(
                    height: 120,
                    child: TextFieldEditor(
                      fieldKey: _fieldEditorKey('post', model!.id, side),
                      initialValue: model!.postRequestScript,
                      readOnly: true,
                    ),
                  ),
              change: _fieldChangeKind(
                model!.postRequestScript,
                otherModel?.postRequestScript,
                side,
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestNoContentColumn extends StatelessWidget {
  const _RequestNoContentColumn({
    required this.referenceModel,
    required this.slots,
  });

  final RequestModel referenceModel;
  final _RequestDiffSlots slots;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget section(String label, Widget child) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer6,
          child,
          kVSpacer10,
        ],
      );
    }

    return SingleChildScrollView(
      padding: kP12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (slots.showName) ...[const _GitDiffNoContentBox(), kVSpacer8],
          if (slots.showDescription) ...[
            const _GitDiffNoContentBox(),
            kVSpacer10,
          ],
          if (slots.showType) ...[const _GitDiffNoContentBox(), kVSpacer10],
          if (slots.showRestLine) ...[
            const _GitDiffRestLinePlaceholder(),
            kVSpacer10,
          ],
          if (slots.showAi) ...[
            referenceModel.aiRequestModel == null
                ? const _GitDiffNoContentBox(minHeight: 220)
                : _AiRequestNoContentBody(ai: referenceModel.aiRequestModel!),
            kVSpacer10,
          ],
          if (slots.showAuth) ...[const _GitDiffNoContentBox(), kVSpacer10],
          if (slots.showHeaders)
            section(kLabelHeaders, const _GitDiffNoContentBox()),
          if (slots.showParams)
            section(kLabelURLParams, const _GitDiffNoContentBox()),
          if (slots.showBody)
            section(kLabelBody, const _GitDiffNoContentBox(minHeight: 160)),
          if (slots.showGraphqlQuery)
            section(kLabelQuery, const _GitDiffNoContentBox(minHeight: 160)),
          if (slots.showPreScript)
            section(
              kLabelPreRequest,
              const _GitDiffNoContentBox(minHeight: 120),
            ),
          if (slots.showPostScript)
            section(
              kLabelPostResponse,
              const _GitDiffNoContentBox(minHeight: 120),
            ),
        ],
      ),
    );
  }
}

class _AiRequestDiffBody extends StatelessWidget {
  const _AiRequestDiffBody({
    required this.ai,
    required this.otherAi,
    required this.side,
    required this.idSuffix,
  });

  final AIRequestModel ai;
  final AIRequestModel? otherAi;
  final _DiffSide side;
  final String idSuffix;

  @override
  Widget build(BuildContext context) {
    final meta = <String, String>{
      if (ai.modelApiProvider != null) 'Provider': ai.modelApiProvider!.name,
      if (ai.model != null && ai.model!.trim().isNotEmpty) 'Model': ai.model!,
      if (ai.stream != null) 'Stream': ai.stream! ? 'true' : 'false',
    };
    final otherMeta = <String, String>{
      if (otherAi?.modelApiProvider != null)
        'Provider': otherAi!.modelApiProvider!.name,
      if (otherAi?.model != null && otherAi!.model!.trim().isNotEmpty)
        'Model': otherAi!.model!,
      if (otherAi?.stream != null)
        'Stream': otherAi!.stream! ? 'true' : 'false',
    };

    final configs = ai.getModelConfigMap().map(
      (key, value) => MapEntry(key, '${value ?? ''}'),
    );
    final otherConfigs =
        otherAi?.getModelConfigMap().map(
          (key, value) => MapEntry(key, '${value ?? ''}'),
        ) ??
        const <String, String>{};

    Widget section(
      String label,
      Widget child, {
      GitDiffChangeKind? change,
      String? subtitle,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GitDiffSectionHeader(
            label: label,
            change: change,
            subtitle: subtitle,
          ),
          _GitDiffChangedBox(change: change, child: child),
          kVSpacer10,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (meta.isNotEmpty || otherMeta.isNotEmpty)
          section(
            'Model',
            meta.isEmpty
                ? const _GitDiffNoContentBox()
                : _GitDiffKeyValueList(
                  rows: meta,
                  otherRows: otherMeta,
                  side: side,
                ),
            change: _fieldChangeKind(meta, otherMeta, side),
            subtitle: '${meta.length} setting${meta.length == 1 ? '' : 's'}',
          ),
        if (ai.url.trim().isNotEmpty ||
            (otherAi?.url.trim().isNotEmpty ?? false))
          section(
            'URL',
            ai.url.trim().isEmpty
                ? const _GitDiffNoContentBox()
                : ReadOnlyTextField(initialValue: ai.url, style: kCodeStyle),
            change: _fieldChangeKind(ai.url, otherAi?.url, side),
          ),
        if (ai.systemPrompt.trim().isNotEmpty ||
            (otherAi?.systemPrompt.trim().isNotEmpty ?? false))
          section(
            kLabelSystemPrompt,
            ai.systemPrompt.trim().isEmpty
                ? const _GitDiffNoContentBox(minHeight: 120)
                : SizedBox(
                  height: 120,
                  child: TextFieldEditor(
                    fieldKey: _fieldEditorKey('ai-system', idSuffix, side),
                    initialValue: ai.systemPrompt,
                    readOnly: true,
                  ),
                ),
            change: _fieldChangeKind(
              ai.systemPrompt,
              otherAi?.systemPrompt,
              side,
            ),
          ),
        if (ai.userPrompt.trim().isNotEmpty ||
            (otherAi?.userPrompt.trim().isNotEmpty ?? false))
          section(
            kLabelUserPromptInput,
            ai.userPrompt.trim().isEmpty
                ? const _GitDiffNoContentBox(minHeight: 120)
                : SizedBox(
                  height: 120,
                  child: TextFieldEditor(
                    fieldKey: _fieldEditorKey('ai-user', idSuffix, side),
                    initialValue: ai.userPrompt,
                    readOnly: true,
                  ),
                ),
            change: _fieldChangeKind(ai.userPrompt, otherAi?.userPrompt, side),
          ),
        if (configs.isNotEmpty || otherConfigs.isNotEmpty)
          section(
            'Model Config',
            configs.isEmpty
                ? const _GitDiffNoContentBox()
                : _GitDiffKeyValueList(
                  rows: configs,
                  otherRows: otherConfigs,
                  side: side,
                ),
            change: _fieldChangeKind(configs, otherConfigs, side),
            subtitle:
                '${configs.length} config${configs.length == 1 ? '' : 's'}',
          ),
      ],
    );
  }
}

class _AiRequestNoContentBody extends StatelessWidget {
  const _AiRequestNoContentBody({required this.ai});

  final AIRequestModel ai;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final configs = ai.getModelConfigMap();
    final hasMeta =
        ai.modelApiProvider != null ||
        (ai.model?.trim().isNotEmpty ?? false) ||
        ai.stream != null;

    Widget section(String label, Widget child) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer6,
          child,
          kVSpacer10,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasMeta) section('Model', const _GitDiffNoContentBox()),
        if (ai.url.trim().isNotEmpty)
          section('URL', const _GitDiffNoContentBox()),
        if (ai.systemPrompt.trim().isNotEmpty)
          section(
            kLabelSystemPrompt,
            const _GitDiffNoContentBox(minHeight: 120),
          ),
        if (ai.userPrompt.trim().isNotEmpty)
          section(
            kLabelUserPromptInput,
            const _GitDiffNoContentBox(minHeight: 120),
          ),
        if (configs.isNotEmpty)
          section('Model Config', const _GitDiffNoContentBox()),
      ],
    );
  }
}

class _GitDiffKeyValueList extends StatelessWidget {
  const _GitDiffKeyValueList({
    required this.rows,
    required this.otherRows,
    required this.side,
  });

  final Map<String, String> rows;
  final Map<String, String> otherRows;
  final _DiffSide side;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keys = _orderedKeys(rows, otherRows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GitDiffKvTableHeader(),
        for (final key in keys)
          _GitDiffChangedBox(
            change: _mapEntryChangeKind(
              key: key,
              value: rows[key],
              otherRows: otherRows,
              side: side,
            ),
            margin: const EdgeInsets.only(bottom: 6),
            child:
                rows.containsKey(key)
                    ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            key,
                            style: kCodeStyle.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        kHSpacer8,
                        Expanded(
                          flex: 3,
                          child: Text(
                            rows[key] ?? '',
                            style: kCodeStyle.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    )
                    : const _GitDiffNoContentBox(
                      margin: EdgeInsets.symmetric(vertical: 2),
                    ),
          ),
      ],
    );
  }
}

class _GitDiffFormDataList extends StatelessWidget {
  const _GitDiffFormDataList({
    required this.rows,
    required this.otherRows,
    required this.side,
  });

  final List<FormDataModel> rows;
  final List<FormDataModel> otherRows;
  final _DiffSide side;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mergedRows = _orderedFormDataRows(rows, otherRows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GitDiffKvTableHeader(keyLabel: 'Name', valueLabel: 'Value'),
        for (final entry in mergedRows)
          _GitDiffChangedBox(
            change:
                entry == null
                    ? null
                    : _formDataChangeKind(
                      row: entry,
                      otherRows: otherRows,
                      side: side,
                    ),
            margin: const EdgeInsets.only(bottom: 6),
            child:
                entry == null
                    ? const _GitDiffNoContentBox(
                      margin: EdgeInsets.symmetric(vertical: 2),
                    )
                    : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.name,
                            style: kCodeStyle.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                        kHSpacer8,
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.value,
                                style: kCodeStyle.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              if (entry.type == FormDataType.file)
                                Text(
                                  entry.type.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
          ),
      ],
    );
  }
}

class _GitDiffNoContentBox extends StatelessWidget {
  const _GitDiffNoContentBox({
    this.minHeight = 36,
    this.width,
    this.margin = EdgeInsets.zero,
  });

  final double minHeight;
  final double? width;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GitDiffBoxedContent(
      minHeight: minHeight,
      margin: margin,
      child: SizedBox(
        width: width,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            kMsgNoContent,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

class _GitDiffRestLinePlaceholder extends StatelessWidget {
  const _GitDiffRestLinePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _GitDiffNoContentBox(width: 56),
        kHSpacer12,
        Expanded(child: _GitDiffNoContentBox()),
      ],
    );
  }
}

class _GitDiffChangedBox extends StatelessWidget {
  const _GitDiffChangedBox({
    required this.child,
    this.change,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final GitDiffChangeKind? change;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return GitDiffBoxedContent(
      change: change,
      margin: margin,
      child: child,
    );
  }
}

GitDiffChangeKind? _fieldChangeKind(
  Object? value,
  Object? otherValue,
  _DiffSide side,
) {
  if (_diffValueEquals(value, otherValue)) return null;

  final hasValue = _hasDiffValue(value);
  final hasOtherValue = _hasDiffValue(otherValue);
  if (!hasValue && !hasOtherValue) return null;
  if (!hasOtherValue && hasValue) {
    return side == _DiffSide.current
        ? GitDiffChangeKind.added
        : GitDiffChangeKind.removed;
  }
  if (hasOtherValue && !hasValue) {
    return null;
  }
  return GitDiffChangeKind.modified;
}

GitDiffChangeKind? _mapEntryChangeKind({
  required String key,
  required String? value,
  required Map<String, String> otherRows,
  required _DiffSide side,
}) {
  if (value == null) return null;
  if (!otherRows.containsKey(key)) {
    return side == _DiffSide.current
        ? GitDiffChangeKind.added
        : GitDiffChangeKind.removed;
  }
  return otherRows[key] == value ? null : GitDiffChangeKind.modified;
}

List<String> _orderedKeys(
  Map<String, String> rows,
  Map<String, String> otherRows,
) {
  return [
    ...rows.keys,
    for (final key in otherRows.keys)
      if (!rows.containsKey(key)) key,
  ];
}

GitDiffChangeKind? _formDataChangeKind({
  required FormDataModel row,
  required List<FormDataModel> otherRows,
  required _DiffSide side,
}) {
  final other = _matchingFormData(row, otherRows);
  if (other == null) {
    return side == _DiffSide.current
        ? GitDiffChangeKind.added
        : GitDiffChangeKind.removed;
  }
  return other.value == row.value && other.type == row.type
      ? null
      : GitDiffChangeKind.modified;
}

FormDataModel? _matchingFormData(FormDataModel row, List<FormDataModel> rows) {
  for (final candidate in rows) {
    if (candidate.name == row.name) return candidate;
  }
  return null;
}

List<FormDataModel?> _orderedFormDataRows(
  List<FormDataModel> rows,
  List<FormDataModel> otherRows,
) {
  return [
    ...rows,
    for (final row in otherRows)
      if (_matchingFormData(row, rows) == null) null,
  ];
}

bool _diffValueEquals(Object? a, Object? b) {
  if (a is String || b is String) {
    return (a?.toString() ?? '') == (b?.toString() ?? '');
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }
  return a == b;
}

bool _hasDiffValue(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

bool _hasConfiguredAuth(HttpRequestModel? model) {
  return _configuredAuthType(model) != null;
}

APIAuthType? _configuredAuthType(HttpRequestModel? model) {
  final type = model?.authModel?.type;
  return type == null || type == APIAuthType.none ? null : type;
}

String _requestBodySignature(HttpRequestModel model) {
  if (model.bodyContentType == ContentType.formdata) {
    return '${model.bodyContentType.name}:'
        '${model.formDataList.map(_formDataSignature).join('|')}';
  }
  return '${model.bodyContentType.name}:${model.body ?? ''}';
}

String _formDataSignature(FormDataModel row) {
  return '${row.name}\u0000${row.type.name}\u0000${row.value}';
}

String _fieldEditorKey(String prefix, String id, _DiffSide side) {
  return 'git-diff-${side.name}-$prefix-$id';
}

class GitDiffEmptyState extends StatelessWidget {
  const GitDiffEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: kP20,
        child: Text(
          kMsgNoContent,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
