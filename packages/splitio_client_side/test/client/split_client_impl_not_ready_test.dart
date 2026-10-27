import 'package:splitio_client_side/src/client/split_client.dart';
import 'package:splitio_commons/src/engine/targeting_engine.dart';
import 'package:splitio_commons/src/event_tracker/events_store.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/impressions/impression_strategy.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/impressions/impressions_observer.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

class _NullEvaluator extends LocalEvaluator {
  int calls = 0;
  _NullEvaluator()
      : super(
          engine: TargetingEngine(),
          ruleStore: InMemoryRuleStore(),
          rbsStore: InMemoryRuleBasedSegmentStore(),
          membershipStore: InMemoryMembershipStore(),
        );

  @override
  EngineEvaluationResult? evaluate(String matchingKey, String? bucketingKey,
      String flag, Attributes attributes) {
    calls++;
    return null;
  }
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
  late InMemoryImpressionsStore store;
  late EventsManager em;
  late _NullEvaluator evaluator;
  late SplitClientImpl client;

  setUp(() {
    store = InMemoryImpressionsStore();
    em = EventsManager();
    evaluator = _NullEvaluator();
    final log = SplitLogger(level: LogLevel.none);
    client = SplitClientImpl(
      key: const Key(matchingKey: 'user1'),
      evaluator: evaluator,
      impressions: ImpressionsManager(
        sdkVersion: 'dart_test-1.0.0',
        strategy: DebugImpressionStrategy(
            observer: ImpressionsObserver(), store: store),
        consentProvider: () => ConsentStatus.granted,
        log: log,
      ),
      eventsManager: em,
      eventsTracker: EventsTracker(
        store: InMemoryEventsStore(),
        consentProvider: () => ConsentStatus.granted,
        log: log,
      ),
      ruleStore: InMemoryRuleStore()
        ..applyChange(Change(changeNumber: 1, updates: {
          'flag_a': _splitWithSet('flag_a', 'set_a'),
        })),
      logger: log,
      flushRecorders: () async {},
    );
  });

  test('getTreatment before READY records a "not ready" impression', () {
    expect(client.getTreatment('flag_a'), 'control');
    final recorded = store.popAll();
    expect(recorded, hasLength(1));
    expect(recorded.single.feature, 'flag_a');
    expect(recorded.single.keyName, 'user1');
    expect(recorded.single.treatment, 'control');
    expect(recorded.single.label, 'not ready');
    expect(recorded.single.changeNumber, isNull);
    expect(evaluator.calls, 0);
  });

  test('getTreatmentsWithConfig before READY records one per valid flag', () {
    final r = client.getTreatmentsWithConfig(['a', 'b']);
    expect(r.values.map((e) => e.treatment), ['control', 'control']);
    expect(store.popAll().map((i) => i.feature), ['a', 'b']);
  });

  test(
      'by-flag-sets before READY returns empty and records nothing even when '
      'a split matches the flag set', () {
    expect(client.getTreatmentsByFlagSets(['set_a']), isEmpty);
    expect(client.getTreatmentsWithConfigByFlagSets(['set_a']), isEmpty);
    expect(store.popAll(), isEmpty);
  });

  test('invalid flag name before READY records no impression', () {
    expect(client.getTreatment(''), 'control');
    expect(store.popAll(), isEmpty);
  });

  test('destroyed client before READY records no impression', () async {
    await client.destroy();
    expect(client.getTreatment('flag_a'), 'control');
    expect(store.popAll(), isEmpty);
  });
}
