import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:test/test.dart';

void main() {
  group('classifyStatus (spec §10.3 taxonomy)', () {
    test('200 → apply', () {
      expect(classifyStatus(200), HttpStatusAction.apply);
    });

    test('304 → notModified', () {
      expect(classifyStatus(304), HttpStatusAction.notModified);
    });

    test('401 → authFailure', () {
      expect(classifyStatus(401), HttpStatusAction.authFailure);
    });

    test('403 → authFailure', () {
      expect(classifyStatus(403), HttpStatusAction.authFailure);
    });

    test('414 → uriTooLong', () {
      expect(classifyStatus(414), HttpStatusAction.uriTooLong);
    });

    test('429 → transientRetry', () {
      expect(classifyStatus(429), HttpStatusAction.transientRetry);
    });

    test('5xx → transientRetry', () {
      for (final code in [500, 501, 502, 503, 504, 599]) {
        expect(classifyStatus(code), HttpStatusAction.transientRetry,
            reason: '$code should be transientRetry');
      }
    });

    test('other 4xx → doNotRetry', () {
      for (final code in [400, 402, 404, 405, 409, 410, 418, 422, 499]) {
        expect(classifyStatus(code), HttpStatusAction.doNotRetry,
            reason: '$code should be doNotRetry');
      }
    });

    group('boundaries', () {
      test('428 (just below 429) → doNotRetry', () {
        expect(classifyStatus(428), HttpStatusAction.doNotRetry);
      });

      test('430 (just above 429) → doNotRetry', () {
        expect(classifyStatus(430), HttpStatusAction.doNotRetry);
      });

      test('499 vs 500 boundary', () {
        expect(classifyStatus(499), HttpStatusAction.doNotRetry);
        expect(classifyStatus(500), HttpStatusAction.transientRetry);
      });

      test('413 (just below 414) → doNotRetry', () {
        expect(classifyStatus(413), HttpStatusAction.doNotRetry);
      });

      test('415 (just above 414) → doNotRetry', () {
        expect(classifyStatus(415), HttpStatusAction.doNotRetry);
      });

      test('400 (first 4xx) → doNotRetry', () {
        expect(classifyStatus(400), HttpStatusAction.doNotRetry);
      });
    });

    group('non-taxonomy statuses fall through to doNotRetry', () {
      test('3xx other than 304', () {
        for (final code in [300, 301, 302, 303, 307, 308]) {
          expect(classifyStatus(code), HttpStatusAction.doNotRetry,
              reason: '$code should be doNotRetry');
        }
      });

      test('2xx other than 200 → apply', () {
        for (final code in [201, 202, 204, 206, 299]) {
          expect(classifyStatus(code), HttpStatusAction.apply,
              reason: '$code should be apply');
        }
      });

      test('1xx', () {
        for (final code in [100, 101, 103]) {
          expect(classifyStatus(code), HttpStatusAction.doNotRetry,
              reason: '$code should be doNotRetry');
        }
      });

      test('nonsensical / zero / negative', () {
        expect(classifyStatus(0), HttpStatusAction.doNotRetry);
        expect(classifyStatus(-1), HttpStatusAction.doNotRetry);
      });

      test('600+ (above 5xx range) → transientRetry (>= 500)', () {
        expect(classifyStatus(600), HttpStatusAction.transientRetry);
      });
    });
  });

  group('StreamingResponse.action getter', () {
    StreamingResponse build(int status) => StreamingResponse(
          statusCode: status,
          lines: const Stream.empty(),
          onClose: () async {},
        );

    test('delegates to classifyStatus', () {
      expect(build(200).action, HttpStatusAction.apply);
      expect(build(401).action, HttpStatusAction.authFailure);
      expect(build(429).action, HttpStatusAction.transientRetry);
      expect(build(414).action, HttpStatusAction.uriTooLong);
      expect(build(404).action, HttpStatusAction.doNotRetry);
      expect(build(304).action, HttpStatusAction.notModified);
    });
  });
}
