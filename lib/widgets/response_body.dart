import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:apidash/models/models.dart';
import 'package:apidash/utils/utils.dart';
import 'package:apidash/consts.dart';
import 'error_message.dart';
import 'response_body_success.dart';

class ResponseBody extends StatelessWidget {
  const ResponseBody({
    super.key,
    this.selectedRequestModel,
    this.isPartOfHistory = false,
  });

  final RequestModel? selectedRequestModel;
  final bool isPartOfHistory;

  @override
  Widget build(BuildContext context) {
    final responseModel = selectedRequestModel?.httpResponseModel;
    if (responseModel == null) {
      return const ErrorMessage(
        message: '$kNullResponseModelError $kUnexpectedRaiseIssue',
      );
    }

    final mediaType =
        responseModel.mediaType ?? MediaType(kTypeText, kSubTypePlain);
    final body = responseModel.body ?? '';
    final bytes = responseModel.bodyBytes ?? _bytesFromBody(responseModel.body);

    if (body.isEmpty && (bytes == null || bytes.isEmpty)) {
      return const ErrorMessage(
        message: kMsgNoContent,
        showIcon: false,
        showIssueButton: false,
      );
    }
    // Fix #415: Treat null Content-type as plain text instead of Error message
    // if (mediaType == null) {
    //   return ErrorMessage(
    //       message:
    //           '$kMsgUnknowContentType - ${responseModel.contentType}. $kUnexpectedRaiseIssue');
    // }

    var responseBodyView = selectedRequestModel?.apiType == APIType.ai
        ? (kAnswerRawBodyViewOptions, kSubTypePlain)
        : getResponseBodyViewOptions(mediaType);
    var options = responseBodyView.$1;
    var highlightLanguage = responseBodyView.$2;

    final isSSE = responseModel.sseOutput?.isNotEmpty ?? false;
    var formattedBody = isSSE
        ? responseModel.sseOutput!.join('\n')
        : responseModel.formattedBody;

    if (formattedBody == null) {
      options = [...options];
      options.remove(ResponseBodyView.code);
    }

    return ResponseBodySuccess(
      key: Key("${selectedRequestModel!.id}-response"),
      mediaType: mediaType,
      options: options,
      bytes: bytes ?? Uint8List(0),
      body: body,
      formattedBody: formattedBody,
      highlightLanguage: highlightLanguage,
      sseOutput: responseModel.sseOutput,
      isAIResponse: selectedRequestModel?.apiType == APIType.ai,
      aiRequestModel: selectedRequestModel?.aiRequestModel,
      isPartOfHistory: isPartOfHistory,
    );
  }

  Uint8List? _bytesFromBody(String? body) {
    if (body == null) {
      return null;
    }
    return Uint8List.fromList(utf8.encode(body));
  }
}
