import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/impressions/unique_keys_tracker.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/enums.dart';
import 'package:splitio_commons/src/sync/recorders/unique_keys_recorder.dart';
import 'package:test/test.dart';

void main() {
  group('UniqueKeysRecorder', () {
    late UniqueKeysTracker tracker;
    late List<http.Request> capturedRequests;

    setUp(() {
      tracker = UniqueKeysTracker();
      capturedRequests = [];
    });

    UniqueKeysRecorder makeRecorder({
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
      return UniqueKeysRecorder(
        tracker: tracker,
        consentProvider: () => consent,
        httpClient: client,
        url: 'https://telemetry.split.io/api',
        log: SplitLogger(level: LogLevel.none),
      );
    }

    test('flush does nothing when tracker is empty', () async {
      final recorder = makeRecorder();

      await recorder.flush();

      expect(capturedRequests, isEmpty);
    });

    test('flush serializes key-centric: each k has correct fs list', () async {
      tracker.track('feat_a', 'user1');
      tracker.track('feat_b', 'user1');
      tracker.track('feat_a', 'user2');

      final recorder = makeRecorder();
      await recorder.flush();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      final keys = body['keys'] as List;
      expect(keys, hasLength(2));

      final typedKeys = keys.cast<Map<String, dynamic>>();
      final user1Entry = typedKeys.firstWhere((e) => e['k'] == 'user1');
      expect(user1Entry['fs'], containsAll(['feat_a', 'feat_b']));

      final user2Entry = typedKeys.firstWhere((e) => e['k'] == 'user2');
      expect(user2Entry['fs'], equals(['feat_a']));
    });

    test('flush skips when consent is unknown', () async {
      tracker.track('feat', 'key');

      final recorder = makeRecorder(consent: ConsentStatus.unknown);
      await recorder.flush();

      expect(capturedRequests, isEmpty);
    });

    test('flush posts to correct URL', () async {
      tracker.track('feat', 'key');

      final recorder = makeRecorder();
      await recorder.flush();

      expect(capturedRequests.first.url.toString(),
          'https://telemetry.split.io/api/v1/keys/cs');
    });

    test('flush handles HTTP errors gracefully', () async {
      tracker.track('feat', 'key');

      final recorder = makeRecorder(
        mockClient: MockClient((req) async => throw Exception('network error')),
      );

      await expectLater(recorder.flush(), completes);
    });

    test('flush clears tracker after posting', () async {
      tracker.track('feat', 'key');

      final recorder = makeRecorder();
      await recorder.flush();

      await recorder.flush();
      expect(capturedRequests, hasLength(1));
    });

    test('pushRateSeconds is 900', () {
      final recorder = makeRecorder();
      expect(recorder.pushRateSeconds, 900);
    });
  });
}
