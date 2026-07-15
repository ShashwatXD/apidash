import 'package:apidash/consts.dart';
import 'package:apidash/models/request_model.dart';
import 'package:apidash/widgets/widgets.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:apidash_design_system/apidash_design_system.dart';
import 'package:flutter/material.dart';

import 'git_diff_chrome.dart';
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

List<GitDiffChangedField> collectResponseDiffChanges({
  required HttpResponseModel? original,
  required HttpResponseModel? current,
}) {
  final changes = <GitDiffChangedField>[];

  void add(String label, Object? a, Object? b, {String? detail}) {
    final kind = _responsePairKind(a, b);
    if (kind == null) return;
    changes.add(GitDiffChangedField(label: label, kind: kind, detail: detail));
  }

  add(
    'Status',
    original?.statusCode,
    current?.statusCode,
    detail:
        '${original?.statusCode ?? '—'} → ${current?.statusCode ?? '—'}',
  );
  add(
    'Time',
    original?.time?.inMilliseconds,
    current?.time?.inMilliseconds,
    detail:
        '${_formatDuration(original?.time)} → ${_formatDuration(current?.time)}',
  );
  add(
    'Headers',
    original?.headers,
    current?.headers,
    detail:
        '${original?.headers?.length ?? 0} → ${current?.headers?.length ?? 0}',
  );
  add(
    'Body',
    original?.body,
    current?.body,
  );
  return changes;
}

GitDiffChangeKind? _responsePairKind(Object? a, Object? b) {
  if (_responseEquals(a, b)) return null;
  final hasA = a != null && (a is! String || a.trim().isNotEmpty);
  final hasB = b != null && (b is! String || b.trim().isNotEmpty);
  if (a is Map) {
    // handled below via equals
  }
  if (!hasA && hasB) return GitDiffChangeKind.added;
  if (hasA && !hasB) return GitDiffChangeKind.removed;
  if (!hasA && !hasB) return null;
  return GitDiffChangeKind.modified;
}

bool _responseEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || '${b[key]}' != '${a[key]}') return false;
    }
    return true;
  }
  return a == b;
}

String _formatDuration(Duration? time) {
  if (time == null) return '—';
  if (time.inMilliseconds < 1000) return '${time.inMilliseconds} ms';
  return '${(time.inMilliseconds / 1000).toStringAsFixed(2)} s';
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
    final changes = collectResponseDiffChanges(
      original: original,
      current: current,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GitDiffChangeSummaryBar(changes: changes),
        Expanded(
          child: GitDiffSideBySideShell(
            original: _ResponseDiffColumn(
              response: original,
              other: current,
              side: _ResponseSide.original,
              raw: originalRaw,
              fieldKey: 'git-diff-response-original',
            ),
            current: _ResponseDiffColumn(
              response: current,
              other: original,
              side: _ResponseSide.current,
              raw: currentRaw,
              fieldKey: 'git-diff-response-current',
            ),
          ),
        ),
      ],
    );
  }
}

enum _ResponseSide { original, current }

class _ResponseDiffColumn extends StatelessWidget {
  const _ResponseDiffColumn({
    required this.response,
    required this.other,
    required this.side,
    required this.raw,
    required this.fieldKey,
  });

  final HttpResponseModel? response;
  final HttpResponseModel? other;
  final _ResponseSide side;
  final String? raw;
  final String fieldKey;

  @override
  Widget build(BuildContext context) {
    if (response == null) {
      if (raw != null && raw!.trim().isNotEmpty) {
        return GitJsonFallbackColumn(raw: raw, fieldKey: fieldKey);
      }
      if (other != null) {
        return _ResponseSkeletonPlaceholder(reference: other!);
      }
      return const GitDiffEmptyState();
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final headers = response!.headers ?? const <String, String>{};
    final otherHeaders = other?.headers ?? const <String, String>{};
    final statusChange = _sideChange(
      response!.statusCode,
      other?.statusCode,
      side,
    );
    final timeChange = _sideChange(
      response!.time?.inMilliseconds,
      other?.time?.inMilliseconds,
      side,
    );
    final headersChange = _sideChange(headers, otherHeaders, side);
    final bodyChange = _sideChange(response!.body, other?.body, side);

    final requestModel = RequestModel(
      id: 'git-diff-response-${side.name}',
      httpResponseModel: response,
    );

    return SingleChildScrollView(
      padding: kP12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GitDiffSectionHeader(
            label: 'Status',
            change: statusChange,
            subtitle: kResponseCodeReasons[response!.statusCode],
          ),
          _Highlight(
            change: statusChange,
            child: Text(
              '${response!.statusCode ?? '—'}',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          kVSpacer10,
          GitDiffSectionHeader(label: 'Time', change: timeChange),
          _Highlight(
            change: timeChange,
            child: Text(
              _formatDuration(response!.time),
              style: kCodeStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          kVSpacer10,
          GitDiffSectionHeader(
            label: kLabelHeaders,
            change: headersChange,
            subtitle:
                '${headers.length} header${headers.length == 1 ? '' : 's'}',
          ),
          _Highlight(
            change: headersChange,
            child: headers.isEmpty
                ? Text(
                    kMsgNoContent,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const GitDiffKvTableHeader(),
                      for (final key in {
                        ...headers.keys,
                        ...otherHeaders.keys,
                      })
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _Highlight(
                            change: _headerEntryChange(
                              key: key,
                              value: headers[key],
                              otherHeaders: otherHeaders,
                              side: side,
                            ),
                            child: headers.containsKey(key)
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          key,
                                          style: kCodeStyle.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      kHSpacer8,
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          headers[key] ?? '',
                                          style: kCodeStyle.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    kMsgNoContent,
                                    style: textTheme.bodySmall?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
          ),
          kVSpacer10,
          GitDiffSectionHeader(
            label: kLabelBody,
            change: bodyChange,
            subtitle: response!.contentType,
          ),
          _Highlight(
            change: bodyChange,
            child: SizedBox(
              height: 280,
              child: ResponseBody(selectedRequestModel: requestModel),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponseSkeletonPlaceholder extends StatelessWidget {
  const _ResponseSkeletonPlaceholder({required this.reference});

  final HttpResponseModel reference;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: kP12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GitDiffSectionHeader(label: 'Status'),
          _emptyBox(context),
          kVSpacer10,
          const GitDiffSectionHeader(label: 'Time'),
          _emptyBox(context),
          kVSpacer10,
          GitDiffSectionHeader(
            label: kLabelHeaders,
            subtitle:
                '${reference.headers?.length ?? 0} header'
                '${(reference.headers?.length ?? 0) == 1 ? '' : 's'} on other side',
          ),
          _emptyBox(context, minHeight: 80),
          kVSpacer10,
          const GitDiffSectionHeader(label: kLabelBody),
          _emptyBox(context, minHeight: 160),
        ],
      ),
    );
  }

  Widget _emptyBox(BuildContext context, {double minHeight = 36}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Text(
        kMsgNoContent,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.child, this.change});

  final Widget child;
  final GitDiffChangeKind? change;

  @override
  Widget build(BuildContext context) {
    return GitDiffBoxedContent(change: change, child: child);
  }
}

GitDiffChangeKind? _sideChange(
  Object? value,
  Object? otherValue,
  _ResponseSide side,
) {
  final kind = _responsePairKind(value, otherValue);
  if (kind == null) return null;
  if (kind == GitDiffChangeKind.added) {
    return side == _ResponseSide.current ? GitDiffChangeKind.added : null;
  }
  if (kind == GitDiffChangeKind.removed) {
    return side == _ResponseSide.original ? GitDiffChangeKind.removed : null;
  }
  return GitDiffChangeKind.modified;
}

GitDiffChangeKind? _headerEntryChange({
  required String key,
  required String? value,
  required Map<String, String> otherHeaders,
  required _ResponseSide side,
}) {
  if (value == null) return null;
  if (!otherHeaders.containsKey(key)) {
    return side == _ResponseSide.current
        ? GitDiffChangeKind.added
        : GitDiffChangeKind.removed;
  }
  return otherHeaders[key] == value ? null : GitDiffChangeKind.modified;
}
