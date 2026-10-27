import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/impressions/unique_keys_tracker.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/enums.dart'
    show ConsentStatus, UniqueKeysPayloadFormat;
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
        sdkVersion: 'dart_test-1.0.0',
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

    test(
        'a transient failure retains the batch and retries on the next '
        'flush cycle (spec §13.1)', () async {
      tracker.track('feat', 'key');
      var attempts = 0;

      final recorder = makeRecorder(
        mockClient: MockClient((req) async {
          attempts++;
          capturedRequests.add(req);
          if (attempts == 1) return http.Response('', 500);
          return http.Response('', 200);
        }),
      );

      await recorder.flush();
      expect(attempts, 1);

      await recorder.flush();
      expect(attempts, 2);
      final body = jsonDecode(capturedRequests.last.body) as Map;
      final keys = (body['keys'] as List).cast<Map<String, dynamic>>();
      expect(keys.first['k'], 'key');
    });

    test(
        'clearRetained drops a batch retained after a failed POST — no '
        'retry on the next flush (spec §7.2)', () async {
      tracker.track('feat', 'key');
      var attempts = 0;

      final recorder = makeRecorder(
        mockClient: MockClient((req) async {
          attempts++;
          return http.Response('', 500);
        }),
      );

      await recorder.flush();
      expect(attempts, 1, reason: 'first POST fails, batch retained');

      recorder.clearRetained();

      await recorder.flush();
      expect(
        attempts,
        1,
        reason: 'retained batch was dropped — no retry POST happened',
      );
    });

    test('pushRateSeconds is 900', () {
      final recorder = makeRecorder();
      expect(recorder.pushRateSeconds, 900);
    });
  });

  group('UniqueKeysRecorder (server-side payload format, spec §19.6)', () {
    late UniqueKeysTracker tracker;
    late List<http.Request> capturedRequests;

    setUp(() {
      tracker = UniqueKeysTracker();
      capturedRequests = [];
    });

    UniqueKeysRecorder makeServerSideRecorder({
      ConsentStatus consent = ConsentStatus.granted,
      http.Client? mockClient,
    }) {
      final client = SplitHttpClient(
        sdkVersion: 'dart_test-1.0.0',
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
        payloadFormat: UniqueKeysPayloadFormat.serverSide,
        httpClient: client,
        url: 'https://telemetry.split.io/api',
        log: SplitLogger(level: LogLevel.none),
      );
    }

    test('flush posts to /v1/keys/ss, not /v1/keys/cs', () async {
      tracker.track('feat', 'key');

      final recorder = makeServerSideRecorder();
      await recorder.flush();

      expect(capturedRequests.first.url.toString(),
          'https://telemetry.split.io/api/v1/keys/ss');
    });

    test('flush serializes feature-centric: each f has correct ks list',
        () async {
      tracker.track('feat_a', 'user1');
      tracker.track('feat_a', 'user2');
      tracker.track('feat_b', 'user1');

      final recorder = makeServerSideRecorder();
      await recorder.flush();

      expect(capturedRequests, hasLength(1));
      final body =
          jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
      final keys = body['keys'] as List;
      expect(keys, hasLength(2));

      final typedKeys = keys.cast<Map<String, dynamic>>();
      final featA = typedKeys.firstWhere((e) => e['f'] == 'feat_a');
      expect(featA['ks'], containsAll(['user1', 'user2']));

      final featB = typedKeys.firstWhere((e) => e['f'] == 'feat_b');
      expect(featB['ks'], equals(['user1']));
    });

    test(
        'a transient failure retains the batch and retries on the next '
        'flush cycle (spec §13.1)', () async {
      tracker.track('feat', 'key');
      var attempts = 0;

      final recorder = makeServerSideRecorder(
        mockClient: MockClient((req) async {
          attempts++;
          capturedRequests.add(req);
          if (attempts == 1) return http.Response('', 500);
          return http.Response('', 200);
        }),
      );

      await recorder.flush();
      expect(attempts, 1);

      await recorder.flush();
      expect(attempts, 2);
      final body = jsonDecode(capturedRequests.last.body) as Map;
      final keys = (body['keys'] as List).cast<Map<String, dynamic>>();
      expect(keys.first['f'], 'feat');
      expect(keys.first['ks'], equals(['key']));
    });
  });
}
