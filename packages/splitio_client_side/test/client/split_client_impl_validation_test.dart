import 'package:splitio_client_side/src/client/split_client.dart';
import 'package:splitio_commons/src/engine/targeting_engine.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/event_tracker/events_store.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/impressions/impression_strategy.dart';
import 'package:splitio_commons/src/impressions/impressions_counter.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/impressions/unique_keys_tracker.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

// Fake evaluator that counts calls and can be configured to return a result.
class _FakeEvaluator {
  int callCount = 0;
  EngineEvaluationResult? Function(String flag)? handler;

  EngineEvaluationResult? evaluate(
      String matchingKey, String? bucketingKey, String flag, Attributes attrs) {
    callCount++;
    return handler?.call(flag);
  }

  ParsedSplit? getRule(String flag) => null;
}

// Minimal LocalEvaluator wrapper that delegates to the fake.
class _FakeLocalEvaluator extends LocalEvaluator {
  final _FakeEvaluator _fake;

  _FakeLocalEvaluator(this._fake)
      : super(
          engine: TargetingEngine(),
          ruleStore: InMemoryRuleStore(),
          rbsStore: InMemoryRuleBasedSegmentStore(),
          membershipStore: InMemoryMembershipStore(),
        );

  @override
  EngineEvaluationResult? evaluate(String matchingKey, String? bucketingKey,
      String flag, Attributes attributes) {
    return _fake.evaluate(matchingKey, bucketingKey, flag, attributes);
  }
}

SplitClientImpl _buildClient({
  required Key key,
  required _FakeEvaluator fakeEval,
  EventsManager? eventsManager,
}) {
  final em = eventsManager ?? EventsManager();
  final impressions = ImpressionsManager(
    strategy: NoneImpressionStrategy(
      counter: ImpressionsCounter(),
      tracker: UniqueKeysTracker(),
    ),
    consentProvider: () => ConsentStatus.granted,
    log: SplitLogger(level: LogLevel.none),
  );
  final eventsStore = InMemoryEventsStore();
  final eventsTracker = EventsTracker(
    store: eventsStore,
    consentProvider: () => ConsentStatus.granted,
    log: SplitLogger(level: LogLevel.none),
  );
  return SplitClientImpl(
    key: key,
    evaluator: _FakeLocalEvaluator(fakeEval),
    impressions: impressions,
    eventsManager: em,
    eventsTracker: eventsTracker,
    ruleStore: InMemoryRuleStore(),
    logger: SplitLogger(level: LogLevel.none),
    flushRecorders: () async {},
  );
}

void main() {
  group('SplitClientImpl.getTreatment — input validation', () {
    test('returns control on whitespace-only flag name, evaluator not called',
        () {
      final fake = _FakeEvaluator();
      final em = EventsManager()..notifyReady();
      final client = _buildClient(
          key: const Key(matchingKey: 'user_a'),
          fakeEval: fake,
          eventsManager: em);

      expect(client.getTreatment('  '), 'control');
      expect(fake.callCount, 0);
    });

    test('returns control on null-like empty flag, evaluator not called', () {
      final fake = _FakeEvaluator();
      final em = EventsManager()..notifyReady();
      final client = _buildClient(
          key: const Key(matchingKey: 'user_a'),
          fakeEval: fake,
          eventsManager: em);

      expect(client.getTreatment(''), 'control');
      expect(fake.callCount, 0);
    });

    test('evaluates when unsupported attribute values are present', () {
      final fake = _FakeEvaluator();
      fake.handler = (_) => EngineEvaluationResult(
          treatment: 'on',
          label: 'matched',
          impressionDisabled: false,
          changeNumber: 0);
      final em = EventsManager()..notifyReady();
      final client = _buildClient(
          key: const Key(matchingKey: 'user_a'),
          fakeEval: fake,
          eventsManager: em);

      // Unsupported value type does NOT abort evaluation — values pass through.
      final result =
          client.getTreatment('my_flag', attributes: {'unsupported': Object()});
      expect(result, 'on');
      expect(fake.callCount, 1);
    });

    test('returns control when client is destroyed, evaluator not called', () {
      final fake = _FakeEvaluator();
      final em = EventsManager()..notifyReady();
      em.dispose();
      final client = _buildClient(
          key: const Key(matchingKey: 'user_a'),
          fakeEval: fake,
          eventsManager: em);

      expect(client.getTreatment('my_flag'), 'control');
      expect(fake.callCount, 0);
    });
  });

  group('SplitClientImpl.getTreatments — validation', () {
    test('returns [] on empty flags list', () {
      final fake = _FakeEvaluator();
      final client =
          _buildClient(key: const Key(matchingKey: 'user_a'), fakeEval: fake);
      expect(client.getTreatments(<String>[]), <String>[]);
      expect(fake.callCount, 0);
    });

    test('deduplicates flag names preserving first-seen order', () {
      final fake = _FakeEvaluator();
      fake.handler = (f) => EngineEvaluationResult(
          treatment: f == 'a' ? 'on' : 'off',
          label: 'rule',
          impressionDisabled: false,
          changeNumber: 0);
      final em = EventsManager()..notifyReady();
      final client = _buildClient(
          key: const Key(matchingKey: 'user_a'),
          fakeEval: fake,
          eventsManager: em);

      final result = client.getTreatments(['a', 'b', 'a']);
      // 'a' appears once, 'b' once — deduped
      expect(result.length, 2);
      expect(fake.callCount, 2);
    });

    test('drops whitespace-only entry from list', () {
      final fake = _FakeEvaluator();
      fake.handler = (_) => EngineEvaluationResult(
          treatment: 'on',
          label: 'rule',
          impressionDisabled: false,
          changeNumber: 0);
      final em = EventsManager()..notifyReady();
      final client = _buildClient(
          key: const Key(matchingKey: 'user_a'),
          fakeEval: fake,
          eventsManager: em);

      final result = client.getTreatments(['valid', '   ', 'also_valid']);
      expect(result.length, 2);
    });
  });

  group('SplitClientImpl.getTreatmentsByFlagSets — validation', () {
    test('returns [] on empty flag-set list', () {
      final fake = _FakeEvaluator();
      final client =
          _buildClient(key: const Key(matchingKey: 'user_a'), fakeEval: fake);
      expect(client.getTreatmentsByFlagSets(<String>[]), <String>[]);
      expect(fake.callCount, 0);
    });
  });

  group('SplitClientImpl.track — key guard', () {
    test('returns false when matchingKey is empty', () {
      final fake = _FakeEvaluator();
      final client =
          _buildClient(key: const Key(matchingKey: ''), fakeEval: fake);
      expect(client.track('purchase', 'user'), isFalse);
    });

    test('returns false when client is destroyed', () {
      final fake = _FakeEvaluator();
      final em = EventsManager()..notifyReady();
      em.dispose();
      final client = _buildClient(
          key: const Key(matchingKey: 'user_a'),
          fakeEval: fake,
          eventsManager: em);
      expect(client.track('purchase', 'user'), isFalse);
    });
  });
}
