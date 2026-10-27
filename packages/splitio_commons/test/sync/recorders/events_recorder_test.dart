import 'dart:convert';

import 'package:splitio_commons/src/event_tracker/event_tracker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/sync.dart';
import 'package:test/test.dart';

Event _event(String id, {int timestamp = 1}) => Event(
      eventTypeId: id,
      trafficTypeName: 'user',
      key: 'user_a',
      timestamp: timestamp,
      value: 1.5,
      properties: const {'k': 'v'},
    );

void main() {
  group('EventsRecorder', () {
    late InMemoryEventsStore store;
    late List<http.Request> capturedRequests;

    setUp(() {
      store = InMemoryEventsStore();
      capturedRequests = [];
    });

    EventsRecorder makeRecorder({
      int pushRateSeconds = 60,
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
      return EventsRecorder(
        store: store,
        httpClient: client,
        url: 'https://events.split.io/api',
        pushRateSeconds: pushRateSeconds,
        log: SplitLogger(level: LogLevel.none),
      );
    }

    test('flush does nothing when store is empty', () async {
      final recorder = makeRecorder();
      await recorder.flush();
      expect(capturedRequests, isEmpty);
    });

    test('flush posts events in wire shape', () async {
      store.push(_event('purchase', timestamp: 1000), 1024);
      store.push(_event('signup', timestamp: 2000), 1024);

      final recorder = makeRecorder();
      await recorder.flush();

      expect(capturedRequests, hasLength(1));
      final req = capturedRequests.first;
      expect(req.url.toString(), 'https://events.split.io/api/events/bulk');

      final body = jsonDecode(req.body) as List;
      expect(body, hasLength(2));

      expect(body[0]['eventTypeId'], 'purchase');
      expect(body[0]['trafficTypeName'], 'user');
      expect(body[0]['key'], 'user_a');
      expect(body[0]['timestamp'], 1000);
      expect(body[0]['value'], 1.5);
      expect(body[0]['properties'], {'k': 'v'});
    });

    test('flush batches into groups of 500', () async {
      for (var i = 0; i < 1200; i++) {
        store.push(_event('purchase', timestamp: i), 100);
      }

      final recorder = makeRecorder();
      await recorder.flush();

      expect(capturedRequests, hasLength(3));
    });

    test(
        'a transient failure retains the batch for the next flush cycle, '
        'then it succeeds (spec §13.1)', () async {
      store.push(_event('purchase'), 1024);
      var attempts = 0;

      final recorder = makeRecorder(
        mockClient: MockClient((req) async {
          attempts++;
          capturedRequests.add(req);
          if (attempts == 1) return http.Response('', 503);
          return http.Response('', 200);
        }),
      );

      await recorder.flush();
      expect(attempts, 1);

      await recorder.flush();
      expect(attempts, 2);
      final body = jsonDecode(capturedRequests.last.body) as List;
      expect(body, hasLength(1));
      expect(body.first['eventTypeId'], 'purchase');
    });

    test('a second consecutive failure drops the batch (spec §13.1)', () async {
      store.push(_event('purchase'), 1024);
      var attempts = 0;

      final recorder = makeRecorder(
        mockClient: MockClient((req) async {
          attempts++;
          return http.Response('', 500);
        }),
      );

      await recorder.flush();
      await recorder.flush();
      expect(attempts, 2);

      await recorder.flush();
      expect(attempts, 2, reason: 'batch was dropped after the retry failed');
    });

    test('a non-retryable 4xx drops the batch immediately (spec §13.1)',
        () async {
      store.push(_event('purchase'), 1024);
      var attempts = 0;

      final recorder = makeRecorder(
        mockClient: MockClient((req) async {
          attempts++;
          return http.Response('', 422);
        }),
      );

      await recorder.flush();
      expect(attempts, 1);

      await recorder.flush();
      expect(attempts, 1, reason: 'no retry for a non-retryable status');
    });

    test(
        'clearRetained drops a batch retained after a failed POST — no '
        'retry on the next flush (spec §7.2)', () async {
      store.push(_event('purchase'), 1024);
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
  });
}
