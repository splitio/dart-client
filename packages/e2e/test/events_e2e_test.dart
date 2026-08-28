import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

void main() {
  group('Events flush on destroy', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test('posts queued events when factory is destroyed', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
          eventsPushRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client(key);
      final ok = client.track(
        'purchase',
        'user',
        value: 9.99,
        properties: {'sku': 'abc-123', 'quantity': 2},
      );
      expect(ok, isTrue);

      expect(backend.eventRequests, isEmpty,
          reason: 'No events posted yet (timer has not fired)');

      await factory.destroy();

      expect(backend.eventRequests, isNotEmpty,
          reason: 'Events flushed on destroy');

      final posted = backend.postedEvents;
      expect(posted, hasLength(1));

      final event = posted.first;
      expect(event['eventTypeId'], 'purchase');
      expect(event['trafficTypeName'], 'user');
      expect(event['key'], 'user_a');
      expect(event['value'], 9.99);
      expect(event['timestamp'], isA<int>());
      expect((event['timestamp'] as int) > 0, isTrue);
      expect(event['properties'], {'sku': 'abc-123', 'quantity': 2});
    });

    test('rejects empty eventType and does not queue', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
          eventsPushRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client(key);
      expect(client.track('', 'user'), isFalse);

      await factory.destroy();
      expect(backend.eventRequests, isEmpty);
    });

    test('client.flush() posts queued events without destroying the SDK',
        () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
          eventsPushRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client(key);
      client.track('purchase', 'user', value: 1.0);

      expect(backend.eventRequests, isEmpty);

      await client.flush();

      expect(backend.eventRequests, isNotEmpty,
          reason: 'flush() should POST queued events');
      expect(backend.postedEvents, hasLength(1));

      await factory.destroy();
    });

    test('flushes events when queue length reaches 5000', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
          eventsPushRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client(key);
      for (var i = 0; i < 5000; i++) {
        client.track('purchase', 'user');
      }

      // Full-queue callback triggers flush; wait a beat for the async POST.
      await Future.delayed(const Duration(milliseconds: 200));

      expect(backend.eventRequests, isNotEmpty,
          reason: 'full-queue callback should have triggered a flush');

      await factory.destroy();
    });

    test('rejects invalid eventType regex and does not queue', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
          eventsPushRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client(key);
      expect(client.track('_bad_start', 'user'), isFalse);

      await factory.destroy();
      expect(backend.eventRequests, isEmpty);
    });

    test('track on shared client after factory.destroy returns false, no POST fires beyond flush-on-destroy', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
          eventsPushRate: 9999,
        ),
        logLevel: LogLevel.error, // Suppress warnings for cleaner output
      );

      final mainKey = Key(matchingKey: 'user_a');
      final sharedKey = Key(matchingKey: 'user_b');
      final factory = SplitFactory.create('fake-api-key', config, mainKey);

      await factory
          .client(mainKey)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final sharedClient = factory.client(sharedKey);
      expect(sharedClient.track('purchase', 'user', value: 1.0), isTrue);

      expect(backend.eventRequests, isEmpty,
          reason: 'Event queued but not POSTed yet (timer has not fired)');

      await factory.destroy();

      final eventCountAfterDestroy = backend.eventRequests.length;
      expect(eventCountAfterDestroy, equals(1),
          reason: 'Flush-on-destroy should have fired exactly one POST');

      // After factory.destroy(), shared client track() should return false
      // and not queue any new events (per-client destroyed flag).
      final trackResult = sharedClient.track('click', 'user', value: 2.0);
      expect(trackResult, isFalse,
          reason:
              'Shared client track after factory.destroy should return false');

      // No additional POST should fire beyond the flush-on-destroy.
      expect(backend.eventRequests.length, equals(eventCountAfterDestroy),
          reason: 'No new events should be queued after destroy');
      final posted = backend.postedEvents;
      expect(posted.length, equals(1),
          reason: 'Only the pre-destroy event should be flushed');
      expect(posted.first['eventTypeId'], equals('purchase'));
    });

    test(
        'shared client track before factory.destroy flushes on destroy (queues are factory-wide)',
        () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
          eventsPushRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final mainKey = Key(matchingKey: 'user_a');
      final sharedKey = Key(matchingKey: 'user_b');
      final factory = SplitFactory.create('fake-api-key', config, mainKey);

      await factory
          .client(mainKey)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final sharedClient = factory.client(sharedKey);
      sharedClient.track('purchase', 'user', value: 5.0);

      expect(backend.eventRequests, isEmpty,
          reason: 'Event should be queued but not POSTed yet');

      await factory.destroy();

      expect(backend.eventRequests, isNotEmpty,
          reason: 'Factory destroy should flush all events (including from shared clients)');
      final posted = backend.postedEvents;
      expect(posted.length, equals(1));
      expect(posted.first['eventTypeId'], equals('purchase'));
      expect(posted.first['key'], equals('user_b'));
    });
  });
}
