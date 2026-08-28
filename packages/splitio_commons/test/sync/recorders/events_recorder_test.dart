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

    EventsRecorder makeRecorder({int pushRateSeconds = 60}) {
      final client = SplitHttpClient(
        apiKey: 'test-api-key',
        client: MockClient((req) async {
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
  });
}
