import 'package:apidash/consts.dart';
import 'package:apidash/models/request_model.dart';
import 'package:apidash/utils/utils.dart';
import 'package:apidash/widgets/widgets.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

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
    return GitDiffSideBySideShell(
      original: _RequestDiffColumn(
        model: original,
        raw: originalRaw,
        fieldKey: 'git-diff-request-original',
      ),
      current: _RequestDiffColumn(
        model: current,
        raw: currentRaw,
        fieldKey: 'git-diff-request-current',
      ),
    );
  }
}

class _RequestDiffColumn extends StatelessWidget {
  const _RequestDiffColumn({
    required this.model,
    required this.raw,
    required this.fieldKey,
  });

  final RequestModel? model;
  final String? raw;
  final String fieldKey;

  @override
  Widget build(BuildContext context) {
    if (model == null) {
      if (raw != null && raw!.trim().isNotEmpty) {
        return GitJsonFallbackColumn(raw: raw, fieldKey: fieldKey);
      }
      return const GitDiffEmptyState();
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final http = model!.httpRequestModel;
    final apiType = model!.apiType;

    return SingleChildScrollView(
      padding: kP12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        if (model!.name.trim().isNotEmpty) ...[
          Text(
            model!.name,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer8,
        ],
        if (model!.description.trim().isNotEmpty) ...[
          Text(
            model!.description,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          kVSpacer10,
        ],
        if (apiType == APIType.rest && http != null) ...[
          Row(
            children: [
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
              kHSpacer12,
              Expanded(
                child: ReadOnlyTextField(
                  initialValue: http.url,
                  style: kCodeStyle,
                ),
              ),
            ],
          ),
          kVSpacer10,
        ],
        if (apiType == APIType.ai && model!.aiRequestModel != null) ...[
          _AiRequestDiffBody(
            ai: model!.aiRequestModel!,
            idSuffix: model!.id,
          ),
          kVSpacer10,
        ],
        if (http != null && http.headersMap.isNotEmpty) ...[
          Text(
            kLabelHeaders,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer6,
          _GitDiffKeyValueList(rows: http.headersMap),
          kVSpacer10,
        ],
        if (http != null && http.paramsMap.isNotEmpty) ...[
          Text(
            kLabelURLParams,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer6,
          _GitDiffKeyValueList(rows: http.paramsMap),
          kVSpacer10,
        ],
        if (apiType == APIType.rest && http != null && http.hasBody) ...[
          Text(
            kLabelBody,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer6,
          SizedBox(
            height: 160,
            child: switch (http.bodyContentType) {
              ContentType.json => JsonTextFieldEditor(
                  fieldKey: 'git-diff-json-${model!.id}',
                  initialValue: http.body,
                  readOnly: true,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ContentType.formdata => _GitDiffFormDataList(rows: http.formData ?? []),
              _ => TextFieldEditor(
                  fieldKey: 'git-diff-body-${model!.id}',
                  initialValue: http.body,
                  readOnly: true,
                ),
            },
          ),
          kVSpacer10,
        ],
        if (apiType == APIType.graphql &&
            http != null &&
            (http.query?.trim().isNotEmpty ?? false)) ...[
          Text(
            kLabelQuery,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer6,
          SizedBox(
            height: 160,
            child: TextFieldEditor(
              fieldKey: 'git-diff-query-${model!.id}',
              initialValue: http.query,
              readOnly: true,
            ),
          ),
          kVSpacer10,
        ],
        if (model!.preRequestScript?.trim().isNotEmpty ?? false) ...[
          Text(
            kLabelPreRequest,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer6,
          SizedBox(
            height: 120,
            child: TextFieldEditor(
              fieldKey: 'git-diff-pre-${model!.id}',
              initialValue: model!.preRequestScript,
              readOnly: true,
            ),
          ),
          kVSpacer10,
        ],
        if (model!.postRequestScript?.trim().isNotEmpty ?? false) ...[
          Text(
            kLabelPostResponse,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          kVSpacer6,
          SizedBox(
            height: 120,
            child: TextFieldEditor(
              fieldKey: 'git-diff-post-${model!.id}',
              initialValue: model!.postRequestScript,
              readOnly: true,
            ),
          ),
        ],
        ],
      ),
    );
  }
}

class _AiRequestDiffBody extends StatelessWidget {
  const _AiRequestDiffBody({required this.ai, required this.idSuffix});

  final AIRequestModel ai;
  final String idSuffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final meta = <String, String>{
      if (ai.modelApiProvider != null) 'Provider': ai.modelApiProvider!.name,
      if (ai.model != null && ai.model!.trim().isNotEmpty) 'Model': ai.model!,
      if (ai.stream != null) 'Stream': ai.stream! ? 'true' : 'false',
    };

    final configs = ai.getModelConfigMap().map(
          (key, value) => MapEntry(key, '${value ?? ''}'),
        );

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
        if (meta.isNotEmpty) section('Model', _GitDiffKeyValueList(rows: meta)),
        if (ai.url.trim().isNotEmpty)
          section(
            'URL',
            ReadOnlyTextField(initialValue: ai.url, style: kCodeStyle),
          ),
        if (ai.systemPrompt.trim().isNotEmpty)
          section(
            kLabelSystemPrompt,
            SizedBox(
              height: 120,
              child: TextFieldEditor(
                fieldKey: 'git-diff-ai-system-$idSuffix',
                initialValue: ai.systemPrompt,
                readOnly: true,
              ),
            ),
          ),
        if (ai.userPrompt.trim().isNotEmpty)
          section(
            kLabelUserPromptInput,
            SizedBox(
              height: 120,
              child: TextFieldEditor(
                fieldKey: 'git-diff-ai-user-$idSuffix',
                initialValue: ai.userPrompt,
                readOnly: true,
              ),
            ),
          ),
        if (configs.isNotEmpty)
          section('Model Config', _GitDiffKeyValueList(rows: configs)),
      ],
    );
  }
}

class _GitDiffKeyValueList extends StatelessWidget {
  const _GitDiffKeyValueList({required this.rows});

  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in rows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    entry.key,
                    style: kCodeStyle.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                kHSpacer8,
                Expanded(
                  flex: 3,
                  child: Text(
                    entry.value,
                    style: kCodeStyle.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GitDiffFormDataList extends StatelessWidget {
  const _GitDiffFormDataList({required this.rows});

  final List<FormDataModel> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
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
                  child: Text(
                    entry.value,
                    style: kCodeStyle.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
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
