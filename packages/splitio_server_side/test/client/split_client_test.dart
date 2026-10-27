import 'package:splitio_commons/src/event_tracker/event.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/impression.dart';
import 'package:splitio_commons/src/models/parsed_split.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';
import 'package:splitio_commons/src/storage/store.dart';
import 'package:splitio_server_side/src/client/split_client.dart';
import 'package:test/test.dart';

// Minimal test-only fakes — enough to prove that:
//   1) getTreatment / getTreatments / track pass the *positional key* through
//      to the evaluator / events tracker,
//   2) all evaluations return "control" before SDK_READY.

class _FakeEvaluator implements LocalEvaluator {
  String? lastMatchingKey;
  String? lastBucketingKey;
  String? lastFlag;
  int callCount = 0;
  @override
  EngineEvaluationResult? evaluate(
    String matchingKey,
    String? bucketingKey,
    String flagName,
    Map<String, Object?> attributes,
  ) {
    callCount++;
    lastMatchingKey = matchingKey;
    lastBucketingKey = bucketingKey;
    lastFlag = flagName;
    return null; // matches "flag does not exist" path → control
  }

  // stubs...
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImpressions implements ImpressionsManager {
  int records = 0;
  final recorded = <KeyImpression>[];
  @override
  void record(KeyImpression impression, bool impressionsDisabled,
      Map<String, Object?>? attributes) {
    records++;
    recorded.add(impression);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEventsManager implements EventsManager {
  bool ready = false;
  bool destroyed = false;
  @override
  bool get isReady => ready;
  @override
  bool get isDestroyed => destroyed;
  @override
  Stream<List<String>> get onUpdated => const Stream.empty();
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturedEvent {
  final Event event;
  final int size;
  _CapturedEvent(this.event, this.size);
}

class _FakeEventsTracker implements EventsTracker {
  final captured = <_CapturedEvent>[];
  @override
  bool track(Event event, int size) {
    captured.add(_CapturedEvent(event, size));
    return true;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SplitClientImpl _client(_FakeEventsManager ev,
    {LocalEvaluator? evaluator,
    EventsTracker? tracker,
    InMemoryRuleStore? ruleStore,
    _FakeImpressions? impressions}) {
  return SplitClientImpl(
    evaluator: evaluator ?? _FakeEvaluator(),
    impressions: impressions ?? _FakeImpressions(),
    eventsManager: ev,
    eventsTracker: tracker ?? _FakeEventsTracker(),
    ruleStore: ruleStore ?? InMemoryRuleStore(),
    logger: SplitLogger(level: LogLevel.error),
    flushRecorders: () async {},
  );
}

ParsedSplit _splitWithSet(String name, String flagSet) => ParsedSplit(
      name: name,
      trafficTypeName: 'user',
      killed: false,
      defaultTreatment: 'off',
      conditions: const [],
      trafficAllocation: 100,
      seed: 1,
      algo: 2,
      changeNumber: 1,
      sets: [flagSet],
    );

void main() {
  group('SplitClientImpl (server-side)', () {
    test('getTreatment returns control before SDK_READY', () {
      final ev = _FakeEventsManager()..ready = false;
      final c = _client(ev);
      expect(c.getTreatment('user-123', 'flag'), equals('control'));
    });

    test(
        'getTreatment before READY records a "not ready" impression without '
        'changeNumber and skips the evaluator', () {
      final ev = _FakeEventsManager()..ready = false;
      final evaluator = _FakeEvaluator();
      final imps = _FakeImpressions();
      final c = _client(ev, evaluator: evaluator, impressions: imps);
      expect(c.getTreatment('user-123', 'flag'), equals('control'));
      expect(evaluator.callCount, 0);
      expect(imps.recorded, hasLength(1));
      expect(imps.recorded.single.feature, 'flag');
      expect(imps.recorded.single.keyName, 'user-123');
      expect(imps.recorded.single.treatment, 'control');
      expect(imps.recorded.single.label, 'not ready');
      expect(imps.recorded.single.changeNumber, isNull);
    });

    test(
        'getTreatments before READY records one impression per valid flag; '
        'invalid input records none', () {
      final ev = _FakeEventsManager()..ready = false;
      final imps = _FakeImpressions();
      final c = _client(ev, impressions: imps);
      expect(c.getTreatments('user-123', ['a', 'b']),
          {'a': 'control', 'b': 'control'});
      expect(imps.recorded.map((i) => i.feature), ['a', 'b']);
      expect(c.getTreatment('', 'a'), 'control');
      expect(c.getTreatment('user-123', ''), 'control');
      expect(imps.recorded, hasLength(2));
    });

    test(
        'ByFlagSets before READY return empty and record nothing even when a '
        'split matches the flag set', () {
      final ev = _FakeEventsManager()..ready = false;
      final evaluator = _FakeEvaluator();
      final imps = _FakeImpressions();
      final ruleStore = InMemoryRuleStore()
        ..applyChange(Change(changeNumber: 1, updates: {
          'flag_a': _splitWithSet('flag_a', 'set_a'),
        }));
      final c = _client(ev,
          evaluator: evaluator, impressions: imps, ruleStore: ruleStore);
      expect(c.getTreatmentsByFlagSets('user-123', ['set_a']), isEmpty);
      expect(
          c.getTreatmentsWithConfigByFlagSets('user-123', ['set_a']), isEmpty);
      expect(evaluator.callCount, 0);
      expect(imps.recorded, isEmpty);
    });

    test('destroyed client records no impression', () async {
      final ev = _FakeEventsManager()..ready = false;
      final imps = _FakeImpressions();
      final c = _client(ev, impressions: imps);
      await c.destroy();
      expect(c.getTreatment('user-123', 'flag'), 'control');
      expect(imps.recorded, isEmpty);
    });

    test('getTreatment passes the positional key through to the evaluator', () {
      final ev = _FakeEventsManager()..ready = true;
      final evaluator = _FakeEvaluator();
      final c = _client(ev, evaluator: evaluator);
      c.getTreatment('user-123', 'flag');
      expect(evaluator.lastMatchingKey, equals('user-123'));
      expect(evaluator.lastFlag, equals('flag'));
    });

    test('track uses the positional key as matchingKey', () {
      final ev = _FakeEventsManager()..ready = true;
      final tracker = _FakeEventsTracker();
      final c = _client(ev, tracker: tracker);
      final ok = c.track('user-42', 'user', 'purchase', value: 9.99);
      expect(ok, isTrue);
      expect(tracker.captured, hasLength(1));
      expect(tracker.captured.single.event.key, equals('user-42'));
      expect(tracker.captured.single.event.trafficTypeName, equals('user'));
      expect(tracker.captured.single.event.eventTypeId, equals('purchase'));
    });

    test('post-destroy: getTreatment returns control, track returns false',
        () async {
      final ev = _FakeEventsManager()..ready = true;
      final c = _client(ev);
      await c.destroy();
      expect(c.getTreatment('user', 'flag'), equals('control'));
      expect(c.track('user', 'user', 'ev'), isFalse);
    });
  });

  group('SplitClientImpl (server-side) — invalid key type', () {
    // A Map (or any other non-String, non-Key object) must never throw —
    // it must fail open the same way an empty String key does today.
    const invalidKey = <String, String>{'not': 'a key'};

    test('getTreatment returns control and does not throw', () {
      final ev = _FakeEventsManager()..ready = true;
      final evaluator = _FakeEvaluator();
      final c = _client(ev, evaluator: evaluator);
      expect(() => c.getTreatment(invalidKey, 'flag'), returnsNormally);
      expect(c.getTreatment(invalidKey, 'flag'), equals('control'));
      expect(evaluator.callCount, equals(0),
          reason: 'invalid key must never reach the evaluator');
    });

    test('getTreatmentWithConfig returns control with null config', () {
      final ev = _FakeEventsManager()..ready = true;
      final c = _client(ev);
      final result = c.getTreatmentWithConfig(invalidKey, 'flag');
      expect(result.treatment, equals('control'));
      expect(result.config, isNull);
    });

    test('getTreatments returns control per flag', () {
      final ev = _FakeEventsManager()..ready = true;
      final c = _client(ev);
      expect(c.getTreatments(invalidKey, ['flag_a', 'flag_b']),
          equals({'flag_a': 'control', 'flag_b': 'control'}));
    });

    test('getTreatmentsWithConfig returns control per flag', () {
      final ev = _FakeEventsManager()..ready = true;
      final c = _client(ev);
      final results =
          c.getTreatmentsWithConfig(invalidKey, ['flag_a', 'flag_b']);
      expect(results.keys.toSet(), {'flag_a', 'flag_b'});
      expect(results.values.map((r) => r.treatment),
          everyElement(equals('control')));
      expect(results.values.every((r) => r.config == null), isTrue);
    });

    test(
        'getTreatmentsByFlagSets returns empty even when a split matches '
        'the flag set', () {
      final ev = _FakeEventsManager()..ready = true;
      final evaluator = _FakeEvaluator();
      final ruleStore = InMemoryRuleStore()
        ..applyChange(Change(changeNumber: 1, updates: {
          'flag_a': _splitWithSet('flag_a', 'set_a'),
        }));
      final c = _client(ev, evaluator: evaluator, ruleStore: ruleStore);
      expect(c.getTreatmentsByFlagSets(invalidKey, ['set_a']), isEmpty);
      expect(evaluator.callCount, equals(0));
    });

    test(
        'getTreatmentsWithConfigByFlagSets returns empty even when a split '
        'matches the flag set', () {
      final ev = _FakeEventsManager()..ready = true;
      final ruleStore = InMemoryRuleStore()
        ..applyChange(Change(changeNumber: 1, updates: {
          'flag_a': _splitWithSet('flag_a', 'set_a'),
        }));
      final c = _client(ev, ruleStore: ruleStore);
      expect(
          c.getTreatmentsWithConfigByFlagSets(invalidKey, ['set_a']), isEmpty);
    });

    test('track returns false and does not throw', () {
      final ev = _FakeEventsManager()..ready = true;
      final tracker = _FakeEventsTracker();
      final c = _client(ev, tracker: tracker);
      expect(() => c.track(invalidKey, 'user', 'click'), returnsNormally);
      expect(c.track(invalidKey, 'user', 'click'), isFalse);
      expect(tracker.captured, isEmpty);
    });

    test('an Object() key also fails open instead of throwing', () {
      final ev = _FakeEventsManager()..ready = true;
      final c = _client(ev);
      final objectKey = Object();
      expect(c.getTreatment(objectKey, 'flag'), equals('control'));
      expect(c.track(objectKey, 'user', 'click'), isFalse);
    });
  });
}
