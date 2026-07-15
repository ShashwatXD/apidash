import 'package:apidash/models/models.dart';
import 'package:apidash/providers/active_collection_providers.dart';
import 'package:apidash_core/apidash_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fingerprint ignores response body differences', () {
    const base = RequestModel(
      id: 'r1',
      name: 'Get users',
      httpRequestModel: HttpRequestModel(
        method: HTTPVerb.get,
        url: 'https://api.example.com/users',
      ),
    );
    final withResponse = base.copyWith(
      httpResponseModel: const HttpResponseModel(statusCode: 200),
    );

    expect(
      requestContentFingerprint(base),
      requestContentFingerprint(withResponse),
    );
  });

  test('fingerprint changes when request URL changes', () {
    const a = RequestModel(
      id: 'r1',
      httpRequestModel: HttpRequestModel(
        method: HTTPVerb.get,
        url: 'https://api.example.com/a',
      ),
    );
    const b = RequestModel(
      id: 'r1',
      httpRequestModel: HttpRequestModel(
        method: HTTPVerb.get,
        url: 'https://api.example.com/b',
      ),
    );

    expect(requestContentFingerprint(a), isNot(requestContentFingerprint(b)));
  });
}
