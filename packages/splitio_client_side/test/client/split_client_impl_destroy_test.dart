import 'package:splitio_client_side/src/client/split_client.dart';
import 'package:splitio_commons/src/engine/targeting_engine.dart';
import 'package:splitio_commons/src/event_tracker/event.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/impression.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/storage/membership_store.dart';
import 'package:splitio_commons/src/storage/rule_based_segment_store.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';
import 'package:test/test.dart';

class _SpyEventsTracker implements EventsTracker {
  final List<Event> trackedEvents = [];

  @override
  bool track(Event event, int sizeInBytes) {
    trackedEvents.add(event);
    return true;
  }
}

class _SpyFlushRecorders {
  int flushCount = 0;
  Future<void> call() async {
    flushCount++;
  }
}

void main() {
  group('SplitClientImpl.destroy', () {
    late SplitClientImpl client;
    late _SpyEventsTracker eventsTracker;
    late _SpyFlushRecorders flushRecorders;
    late EventsManager eventsManager;

    setUp(() {
      eventsTracker = _SpyEventsTracker();
      flushRecorders = _SpyFlushRecorders();
      eventsManager = EventsManager();
      eventsManager.notifyReady();

      client = SplitClientImpl(
        key: const Key(matchingKey: 'test_user'),
        evaluator: LocalEvaluator(
          engine: TargetingEngine(),
          ruleStore: InMemoryRuleStore(),
          rbsStore: InMemoryRuleBasedSegmentStore(),
          membershipStore: InMemoryMembershipStore(),
        ),
        impressions: _FakeImpressionsManager(),
        eventsManager: eventsManager,
        eventsTracker: eventsTracker,
        ruleStore: InMemoryRuleStore(),
        logger: SplitLogger(level: LogLevel.none),
        flushRecorders: flushRecorders.call,
      );
    });

    test('track after destroy returns false and logs error', () async {
      await client.destroy();

      final result = client.track('click', 'user');

      expect(result, isFalse);
      expect(eventsTracker.trackedEvents, isEmpty,
          reason: 'Event should not be queued after destroy');
    });

    test('getTreatment after destroy returns control', () async {
      await client.destroy();

      final treatment = client.getTreatment('some_flag');

      expect(treatment, equals('control'));
    });

    test('getTreatments after destroy returns list of control', () async {
      await client.destroy();

      final treatments = client.getTreatments(['flag1', 'flag2']);

      expect(treatments, equals(['control', 'control']));
    });

    test('getTreatmentsByFlagSets after destroy returns list of control',
        () async {
      await client.destroy();

      final treatments = client.getTreatmentsByFlagSets(['set1']);

      expect(treatments, isEmpty,
          reason: 'No flags in set, so empty list even after destroy');
    });

    test('getTreatmentWithConfig after destroy returns control', () async {
      await client.destroy();

      final result = client.getTreatmentWithConfig('some_flag');

      expect(result.treatment, equals('control'));
      expect(result.config, isNull);
    });

    test('getTreatmentsWithConfig after destroy returns control for all',
        () async {
      await client.destroy();

      final results = client.getTreatmentsWithConfig(['flag1', 'flag2']);

      expect(results.length, equals(2));
      expect(results[0].treatment, equals('control'));
      expect(results[1].treatment, equals('control'));
    });

    test('getTreatmentsWithConfigByFlagSets after destroy returns empty',
        () async {
      await client.destroy();

      final results = client.getTreatmentsWithConfigByFlagSets(['set1']);

      expect(results, isEmpty);
    });

    test('flush after destroy completes without calling flushRecorders again',
        () async {
      await client.destroy();
      final flushCountAfterDestroy = flushRecorders.flushCount;

      await client.flush();

      expect(flushRecorders.flushCount, equals(flushCountAfterDestroy),
          reason:
              'flush() on a destroyed client MUST NOT call flushRecorders (spec §8.5 flush)');
    });

    test('destroy called twice on same client is a safe no-op', () async {
      await client.destroy();
      await client.destroy();

      // Post-destroy behavior remains consistent across repeated calls.
      expect(client.track('click', 'user'), isFalse);
      expect(eventsTracker.trackedEvents, isEmpty);
    });

    test('destroy flushes recorders exactly once (spec §8.5)', () async {
      await client.destroy();

      expect(flushRecorders.flushCount, equals(1),
          reason:
              'client.destroy() MUST perform one final recorder flush (spec §8.5 Client destroy)');
    });

    test('destroy is idempotent — flushRecorders called at most once',
        () async {
      await client.destroy();
      await client.destroy();
      await client.destroy();

      expect(flushRecorders.flushCount, equals(1),
          reason:
              'Repeated destroy() MUST be a safe no-op (second call MUST NOT trigger another flush)');
    });
  });
}

// Minimal fake implementations for testing

class _FakeImpressionsManager implements ImpressionsManager {
  @override
  void record(KeyImpression impression, bool impressionsDisabled,
      Map<String, Object?>? attributes) {}
}
