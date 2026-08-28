import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/impressions/impressions_counter.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/enums.dart';
import 'package:splitio_commons/src/sync/recorders/impressions_count_recorder.dart';
import 'package:test/test.dart';

void main() {
  group('ImpressionsCountRecorder', () {
    late ImpressionsCounter counter;
    late List<http.Request> capturedRequests;

    setUp(() {
      counter = ImpressionsCounter();
      capturedRequests = [];
    });

    ImpressionsCountRecorder makeRecorder({
      ConsentStatus consent = ConsentStatus.granted,
      http.Client? mockClient,
    }) {
      final client = SplitHttpClient(
        apiKey: 'test-api-key',
        client: mockClient ??
            MockClient((req) async {
              capturedRequests.add(req);
              return http.Response('', 200);
            }),
      );
      return ImpressionsCountRecorder(
        counter: counter,
        consentProvider: () => consent,
        httpClient: client,
        url: 'https://events.split.io/api',
        log: SplitLogger(level: LogLevel.none),
      );
    }

    test('flush does nothing when counter is empty', () async {
      final recorder = makeRecorder();

      await recorder.flush();

      expect(capturedRequests, isEmpty);
    });

    test(
        'flush serializes correctly: key split on double-colon, m is int, rc is count',
        () async {
      // record() truncates to hour: (3600000 ~/ 3600000) * 3600000 = 3600000
      counter.record('my_feature', 3600000);
      counter.record('my_feature', 3600500);

      final recorder = makeRecorder();
      await recorder.flush();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      final pf = body['pf'] as List;
      expect(pf, hasLength(1));

      final entry = pf.first as Map<String, dynamic>;
      expect(entry['f'], 'my_feature');
      expect(entry['m'], 3600000);
      expect(entry['rc'], 2);
    });

    test('flush skips when consent is unknown', () async {
      counter.record('feat', 1000);

      final recorder = makeRecorder(consent: ConsentStatus.unknown);
      await recorder.flush();

      expect(capturedRequests, isEmpty);
    });

    test('flush posts to correct URL', () async {
      counter.record('feat', 1000);

      final recorder = makeRecorder();
      await recorder.flush();

      expect(capturedRequests.first.url.toString(),
          'https://events.split.io/api/testImpressions/count');
    });

    test('flush handles HTTP errors gracefully', () async {
      counter.record('feat', 1000);

      final recorder = makeRecorder(
        mockClient: MockClient((req) async => throw Exception('network error')),
      );

      await expectLater(recorder.flush(), completes);
    });

    test('flush retries once on failure then succeeds', () async {
      counter.record('feat', 1000);
      var attempts = 0;

      final recorder = makeRecorder(
        mockClient: MockClient((req) async {
          attempts++;
          capturedRequests.add(req);
          if (attempts == 1) throw Exception('network error');
          return http.Response('', 200);
        }),
      );

      await recorder.flush();

      expect(attempts, 2);
      expect(capturedRequests, hasLength(2));
    });

    test('flush gives up after one retry still fails', () async {
      counter.record('feat', 1000);
      var attempts = 0;

      final recorder = makeRecorder(
        mockClient: MockClient((req) async {
          attempts++;
          throw Exception('network error');
        }),
      );

      await expectLater(recorder.flush(), completes);
      expect(attempts, 2);
    });

    test('flush clears counter after posting', () async {
      counter.record('feat', 1000);

      final recorder = makeRecorder();
      await recorder.flush();

      // second flush should post nothing
      await recorder.flush();
      expect(capturedRequests, hasLength(1));
    });

    test('pushRateSeconds is 1800', () {
      final recorder = makeRecorder();
      expect(recorder.pushRateSeconds, 1800);
    });
  });
}
