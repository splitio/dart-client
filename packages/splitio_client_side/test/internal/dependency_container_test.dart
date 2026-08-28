import 'package:splitio_commons/src/event_tracker/event_tracker.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_client_side/src/internal/dependency_container.dart';
import 'package:test/test.dart';

void main() {
  group('DependencyContainer consent wiring (§7.2)', () {
    test('declining consent drops queued impressions and events', () {
      final di = DependencyContainer.build(
        'valid-sdk-key-123',
        const SplitClientConfig(
          sync: SyncConfig(readyTimeout: 0, streamingEnabled: false),
        ),
      );
      addTearDown(di.dispose);

      di.impressionsStore.push(KeyImpression(
        feature: 'feat',
        keyName: 'key1',
        treatment: 'on',
        label: 'default rule',
        changeNumber: 1,
        time: 1000,
      ));
      di.eventsStore.push(
        Event(
            eventTypeId: 'e',
            trafficTypeName: 'user',
            key: 'key1',
            timestamp: 1),
        10,
      );
      expect(di.impressionsStore.isEmpty, isFalse);
      expect(di.eventsStore.isEmpty, isFalse);

      di.userConsent.setStatus(ConsentStatus.declined);

      expect(di.impressionsStore.isEmpty, isTrue);
      expect(di.eventsStore.isEmpty, isTrue);
    });
  });

  group('DependencyContainer streaming wiring', () {
    test('constructs a StreamingManager when streaming is enabled', () {
      final di = DependencyContainer.build(
        'valid-sdk-key-123',
        const SplitClientConfig(
          sync: SyncConfig(readyTimeout: 0),
        ),
      );
      addTearDown(di.dispose);
      // Streaming is on by default.
      expect(di.config.sync.streamingEnabled, isTrue);
      expect(di.streamingManager, isNotNull);
    });

    test('leaves streaming null (poll-only) when streaming is disabled', () {
      final di = DependencyContainer.build(
        'valid-sdk-key-123',
        const SplitClientConfig(
          sync: SyncConfig(readyTimeout: 0, streamingEnabled: false),
        ),
      );
      addTearDown(di.dispose);
      expect(di.streamingManager, isNull);
    });

    test('honours a custom streaming endpoint', () {
      final di = DependencyContainer.build(
        'valid-sdk-key-123',
        const SplitClientConfig(
          sync: SyncConfig(
            readyTimeout: 0,
            serviceEndpoints:
                ServiceEndpoints(streamingUrl: 'https://streaming.custom.io'),
          ),
        ),
      );
      addTearDown(di.dispose);
      expect(di.streamingManager, isNotNull);
    });

    test('dispose completes cleanly with streaming enabled', () async {
      final di = DependencyContainer.build(
        'valid-sdk-key-123',
        const SplitClientConfig(sync: SyncConfig(readyTimeout: 0)),
      );
      await expectLater(di.dispose(), completes);
    });

    test('dispose is idempotent with streaming enabled (clears JWT cache)',
        () async {
      // Streaming is on by default, so dispose() clears the JwtAuthProvider
      // cache via clearAll(). clearAll() is safe to call repeatedly, so a
      // second dispose() must also complete without throwing.
      final di = DependencyContainer.build(
        'valid-sdk-key-123',
        const SplitClientConfig(sync: SyncConfig(readyTimeout: 0)),
      );
      expect(di.streamingManager, isNotNull);
      await di.dispose();
      await expectLater(di.dispose(), completes);
    });

    test('dispose is idempotent with streaming disabled', () async {
      final di = DependencyContainer.build(
        'valid-sdk-key-123',
        const SplitClientConfig(
          sync: SyncConfig(readyTimeout: 0, streamingEnabled: false),
        ),
      );
      await di.dispose();
      await expectLater(di.dispose(), completes);
    });
  });
}
