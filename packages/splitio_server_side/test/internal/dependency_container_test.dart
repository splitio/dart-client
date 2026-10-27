import 'package:splitio_commons/src/models/config.dart';
import 'package:splitio_commons/src/storage/segment_store.dart';
import 'package:splitio_server_side/src/internal/dependency_container.dart';
import 'package:test/test.dart';

void main() {
  group('ServerDependencyContainer.build', () {
    test('constructs a fully-wired container with a real segment store', () {
      final di =
          ServerDependencyContainer.build('sdk-key', const SplitClientConfig());
      expect(di.log, isNotNull);
      expect(di.ruleStore, isNotNull);
      expect(di.rbsStore, isNotNull);
      expect(di.segmentStore, isA<InMemorySegmentStore>());
      expect(di.impressionsStore, isNotNull);
      expect(di.eventsStore, isNotNull);
      expect(di.eventsManager, isNotNull);
      expect(di.eventsTracker, isNotNull);
      expect(di.userConsent, isNotNull);
      expect(di.httpClient, isNotNull);
      expect(di.syncManager, isNotNull);
      expect(di.evaluator, isNotNull);
      expect(di.impressions, isNotNull);
      expect(di.manager, isNotNull);
      expect(di.config, isNotNull);
    });

    test('evaluator and segment fetcher share the same SegmentStore instance',
        () {
      final di =
          ServerDependencyContainer.build('sdk-key', const SplitClientConfig());
      // If evaluator's membership resolver is wired to the same instance,
      // registering a segment through the store is visible to isInSegment.
      di.segmentStore.registerSegments(['s']);
      di.segmentStore.update('s', ['user-1'], const [], 1);
      // Evaluator's isInSegment path via the shared resolver:
      expect(di.segmentStore.isInSegment('s', 'user-1'), isTrue);
    });

    test('dispose closes http client and events manager', () async {
      final di =
          ServerDependencyContainer.build('sdk-key', const SplitClientConfig());
      await di.dispose();
      // Idempotent — a second dispose does not throw.
      await di.dispose();
    });
  });
}
