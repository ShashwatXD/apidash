import 'package:apidash/consts.dart';
import 'package:apidash/models/request_model.dart';
import 'package:apidash/widgets/widgets.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:flutter/material.dart';

import 'git_diff_side_by_side_shell.dart';
import 'git_json_fallback_column.dart';
import 'git_request_visual_diff.dart' show GitDiffEmptyState;

HttpResponseModel? parseResponseModel(Map<String, Object?>? json) {
  if (json == null) return null;
  try {
    return HttpResponseModel.fromJson(_fixResponseJson(json));
  } catch (_) {
    return null;
  }
}

Map<String, Object?> _fixResponseJson(Map<String, Object?> json) {
  final bytes = json['bodyBytes'];
  if (bytes is List && bytes is! List<int>) {
    return {
      ...json,
      'bodyBytes': bytes.map((e) => (e as num).toInt()).toList(growable: false),
    };
  }
  return json;
}

class GitResponseVisualDiff extends StatelessWidget {
  const GitResponseVisualDiff({
    super.key,
    required this.original,
    required this.current,
    this.originalRaw,
    this.currentRaw,
  });

  final HttpResponseModel? original;
  final HttpResponseModel? current;
  final String? originalRaw;
  final String? currentRaw;

  @override
  Widget build(BuildContext context) {
    return GitDiffSideBySideShell(
      original: _ResponseDiffColumn(
        response: original,
        raw: originalRaw,
        fieldKey: 'git-diff-response-original',
      ),
      current: _ResponseDiffColumn(
        response: current,
        raw: currentRaw,
        fieldKey: 'git-diff-response-current',
      ),
    );
  }
}

class _ResponseDiffColumn extends StatelessWidget {
  const _ResponseDiffColumn({
    required this.response,
    required this.raw,
    required this.fieldKey,
  });

  final HttpResponseModel? response;
  final String? raw;
  final String fieldKey;

  @override
  Widget build(BuildContext context) {
    if (response == null) {
      if (raw != null && raw!.trim().isNotEmpty) {
        return GitJsonFallbackColumn(raw: raw, fieldKey: fieldKey);
      }
      return const GitDiffEmptyState();
    }

    final requestModel = RequestModel(
      id: 'git-diff-response',
      httpResponseModel: response,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsePaneHeader(
          responseStatus: response!.statusCode,
          message: kResponseCodeReasons[response!.statusCode],
          time: response!.time,
        ),
        Expanded(
          child: ResponseBody(
            selectedRequestModel: requestModel,
          ),
        ),
      ],
    );
  }
}
