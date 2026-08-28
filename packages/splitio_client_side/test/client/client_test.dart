import 'package:splitio_client_side/src/client/split_client.dart';
import 'package:splitio_commons/src/events/events.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/impressions/impressions.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

// --- Fakes ---

class FakeLocalEvaluator {
  EngineEvaluationResult? Function(
    String matchingKey,
    String? bucketingKey,
    String flag,
    Attributes attributes,
  )? evaluateHandler;

  ParsedSplit? Function(String flag)? getRuleHandler;

  bool shouldThrow = false;

  EngineEvaluationResult? evaluate(
    String matchingKey,
    String? bucketingKey,
    String flag,
    Attributes attributes,
  ) {
    if (shouldThrow) throw Exception('evaluator error');
    return evaluateHandler?.call(matchingKey, bucketingKey, flag, attributes);
  }

  ParsedSplit? getRule(String flag) {
    return getRuleHandler?.call(flag);
  }
}

/// A testable [SplitClient] that accepts our fakes.
class TestableSplitClient implements SplitClient {
  final Key _key;
  final FakeLocalEvaluator _evaluator;
  final ImpressionsManager _impressions;
  final EventsManager _eventsManager;
  final InMemoryRuleStore _ruleStore;

  TestableSplitClient({
    required Key key,
    required FakeLocalEvaluator evaluator,
    required ImpressionsManager impressions,
    required EventsManager eventsManager,
    required InMemoryRuleStore ruleStore,
  })  : _key = key,
        _evaluator = evaluator,
        _impressions = impressions,
        _eventsManager = eventsManager,
        _ruleStore = ruleStore;

  @override
  String getTreatment(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    return _evaluate(flag, attributes: attributes, opts: opts).treatment;
  }

  @override
  List<String> getTreatments(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    return flags
        .map((f) => getTreatment(f, attributes: attributes, opts: opts))
        .toList();
  }

  @override
  List<String> getTreatmentsByFlagSets(List<String> flagSets,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    final splits = _ruleStore.getByFlagSets(flagSets);
    return splits
        .map((s) => getTreatment(s.name, attributes: attributes, opts: opts))
        .toList();
  }

  @override
  EvaluationResult getTreatmentWithConfig(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    return _evaluate(flag, attributes: attributes, opts: opts);
  }

  @override
  List<EvaluationResult> getTreatmentsWithConfig(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    return flags
        .map((f) =>
            getTreatmentWithConfig(f, attributes: attributes, opts: opts))
        .toList();
  }

  @override
  List<EvaluationResult> getTreatmentsWithConfigByFlagSets(
      List<String> flagSets,
      {Map<String, Object?>? attributes,
      EvaluationOptions? opts}) {
    final splits = _ruleStore.getByFlagSets(flagSets);
    return splits
        .map((s) =>
            getTreatmentWithConfig(s.name, attributes: attributes, opts: opts))
        .toList();
  }

  @override
  bool track(String eventType, String trafficType,
      {double? value, Map<String, Object?>? properties}) {
    if (eventType.isEmpty) return false;
    if (trafficType.isEmpty) return false;
    if (properties != null && properties.length > 300) return false;
    return true;
  }

  @override
  Future<void> whenReady() => _eventsManager.onReady;

  @override
  Future<void> whenTimeout() => _eventsManager.onTimeout;

  @override
  Stream<List<String>> whenUpdated() => _eventsManager.onUpdated;

  @override
  Future<void> flush() async {}

  @override
  Future<void> destroy() async {}

  EvaluationResult _evaluate(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    try {
      if (flag.isEmpty) {
        return const EvaluationResult(treatment: 'control');
      }

      if (!_eventsManager.isReady) {
        return const EvaluationResult(treatment: 'control');
      }

      final matchingKey = _key.matchingKey;
      final bucketingKey = _key.bucketingKey;

      final engineResult = _evaluator.evaluate(
        matchingKey,
        bucketingKey,
        flag,
        attributes ?? const {},
      );

      if (engineResult == null) {
        return const EvaluationResult(treatment: 'control');
      }

      final rule = _evaluator.getRule(flag);
      final config = rule?.configurations[engineResult.treatment];

      _impressions.record(
        KeyImpression(
          feature: flag,
          keyName: matchingKey,
          bucketingKey: bucketingKey,
          treatment: engineResult.treatment,
          label: engineResult.label,
          changeNumber: rule?.changeNumber ?? 0,
          time: DateTime.now().millisecondsSinceEpoch,
          properties: opts?.properties,
        ),
        engineResult.impressionDisabled,
        attributes ?? const {},
      );

      return EvaluationResult(
        treatment: engineResult.treatment,
        config: config,
      );
    } catch (_) {
      return const EvaluationResult(treatment: 'control');
    }
  }
}

// --- Helpers ---

ParsedSplit makeSplit({
  String name = 'test_flag',
  String defaultTreatment = 'off',
  Map<String, String> configurations = const {},
  bool impressionsDisabled = false,
  int changeNumber = 42,
  List<String> sets = const [],
}) {
  return ParsedSplit(
    name: name,
    trafficTypeName: 'user',
    killed: false,
    defaultTreatment: defaultTreatment,
    conditions: [],
    trafficAllocation: 100,
    seed: 1,
    algo: 2,
    changeNumber: changeNumber,
    configurations: configurations,
    impressionsDisabled: impressionsDisabled,
    sets: sets,
  );
}

void main() {
  late FakeLocalEvaluator evaluator;
  late ImpressionsManager impressions;
  late InMemoryImpressionsStore impressionsStore;
  late EventsManager eventsManager;
  late InMemoryRuleStore ruleStore;
  late Key key;

  TestableSplitClient createClient() {
    return TestableSplitClient(
      key: key,
      evaluator: evaluator,
      impressions: impressions,
      eventsManager: eventsManager,
      ruleStore: ruleStore,
    );
  }

  setUp(() {
    evaluator = FakeLocalEvaluator();
    final observer = ImpressionsObserver();
    impressionsStore = InMemoryImpressionsStore();
    impressions = ImpressionsManager(
      strategy:
          DebugImpressionStrategy(observer: observer, store: impressionsStore),
      consentProvider: () => ConsentStatus.granted,
      log: SplitLogger(level: LogLevel.none),
    );
    eventsManager = EventsManager();
    ruleStore = InMemoryRuleStore();
    key = Key(matchingKey: 'user1');
  });

  group('SplitClient.getTreatment', () {
    test('returns control when SDK is not ready', () {
      final client = createClient();
      final result = client.getTreatment('my_flag');
      expect(result, equals('control'));
    });

    test('returns control when flag not in store', () {
      eventsManager.notifyReady();
      evaluator.evaluateHandler = (_, __, ___, ____) => null;
      evaluator.getRuleHandler = (_) => null;

      final client = createClient();
      final result = client.getTreatment('unknown_flag');
      expect(result, equals('control'));
    });

    test('returns engine treatment when flag exists and SDK is ready', () {
      eventsManager.notifyReady();
      evaluator.evaluateHandler = (_, __, flag, ___) {
        if (flag == 'my_flag') {
          return EngineEvaluationResult(
              treatment: 'on',
              label: 'matched',
              impressionDisabled: false,
              changeNumber: 0);
        }
        return null;
      };
      evaluator.getRuleHandler = (flag) {
        if (flag == 'my_flag') return makeSplit(name: 'my_flag');
        return null;
      };

      final client = createClient();
      final result = client.getTreatment('my_flag');
      expect(result, equals('on'));
    });

    test('returns control when evaluator throws', () {
      eventsManager.notifyReady();
      evaluator.shouldThrow = true;

      final client = createClient();
      final result = client.getTreatment('my_flag');
      expect(result, equals('control'));
    });

    test('empty flag name returns control', () {
      eventsManager.notifyReady();
      final client = createClient();
      final result = client.getTreatment('');
      expect(result, equals('control'));
    });

    test('records impression when evaluation succeeds', () {
      eventsManager.notifyReady();
      evaluator.evaluateHandler = (_, __, ___, ____) {
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'matched',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (_) => makeSplit(changeNumber: 99);

      final client = createClient();
      client.getTreatment('my_flag');

      final recorded = impressionsStore.popAll();
      expect(recorded, hasLength(1));
      expect(recorded[0].feature, equals('my_flag'));
      expect(recorded[0].keyName, equals('user1'));
      expect(recorded[0].treatment, equals('on'));
    });

    test('does not record impression when SDK is not ready', () {
      final client = createClient();
      client.getTreatment('my_flag');
      expect(impressionsStore.popAll(), isEmpty);
    });

    test('passes attributes to evaluator', () {
      eventsManager.notifyReady();
      Map<String, Object?>? capturedAttrs;
      evaluator.evaluateHandler = (_, __, ___, attrs) {
        capturedAttrs = attrs;
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'rule',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (_) => makeSplit();

      final client = createClient();
      client.getTreatment('my_flag', attributes: {'plan': 'enterprise'});
      expect(capturedAttrs, equals({'plan': 'enterprise'}));
    });

    test('passes empty attributes to evaluator when none provided', () {
      eventsManager.notifyReady();
      Map<String, Object?>? capturedAttrs;
      evaluator.evaluateHandler = (_, __, ___, attrs) {
        capturedAttrs = attrs;
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'rule',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (_) => makeSplit();

      final client = createClient();
      client.getTreatment('my_flag');
      expect(capturedAttrs, isEmpty);
    });
  });

  group('SplitClient.getTreatmentWithConfig', () {
    test('returns treatment and config', () {
      eventsManager.notifyReady();
      evaluator.evaluateHandler = (_, __, ___, ____) {
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'matched',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (_) => makeSplit(
            configurations: {
              'on': '{"color":"red"}',
              'off': '{"color":"blue"}'
            },
          );

      final client = createClient();
      final result = client.getTreatmentWithConfig('my_flag');

      expect(result.treatment, equals('on'));
      expect(result.config, equals('{"color":"red"}'));
    });

    test('returns null config when treatment has no configuration', () {
      eventsManager.notifyReady();
      evaluator.evaluateHandler = (_, __, ___, ____) {
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'matched',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (_) => makeSplit(configurations: {});

      final client = createClient();
      final result = client.getTreatmentWithConfig('my_flag');

      expect(result.treatment, equals('on'));
      expect(result.config, isNull);
    });

    test('returns control with null config when not ready', () {
      final client = createClient();
      final result = client.getTreatmentWithConfig('my_flag');

      expect(result.treatment, equals('control'));
      expect(result.config, isNull);
    });
  });

  group('SplitClient.getTreatments', () {
    test('returns treatment for each flag', () {
      eventsManager.notifyReady();
      evaluator.evaluateHandler = (_, __, flag, ___) {
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'rule',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (flag) => makeSplit(name: flag);

      final client = createClient();
      final results = client.getTreatments(['flag_a', 'flag_b', 'flag_c']);

      expect(results, hasLength(3));
      expect(results, everyElement(equals('on')));
    });

    test('returns control for each when not ready', () {
      final client = createClient();
      final results = client.getTreatments(['a', 'b']);
      expect(results, everyElement(equals('control')));
    });

    test('passes attributes to each evaluation', () {
      eventsManager.notifyReady();
      final capturedAttrs = <Map<String, Object?>?>[];
      evaluator.evaluateHandler = (_, __, ___, attrs) {
        capturedAttrs.add(attrs);
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'rule',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (flag) => makeSplit(name: flag);

      final client = createClient();
      client.getTreatments(['a', 'b'], attributes: {'age': 30});

      expect(capturedAttrs, hasLength(2));
      expect(capturedAttrs.every((a) => a!['age'] == 30), isTrue);
    });
  });

  group('SplitClient.getTreatmentsByFlagSets', () {
    test('evaluates all flags matching the given sets', () {
      eventsManager.notifyReady();

      ruleStore.applyChange(Change(
        changeNumber: 1,
        updates: {
          'flag_a': makeSplit(name: 'flag_a', sets: ['set1']),
          'flag_b': makeSplit(name: 'flag_b', sets: ['set1', 'set2']),
          'flag_c': makeSplit(name: 'flag_c', sets: ['set3']),
        },
      ));

      evaluator.evaluateHandler = (_, __, flag, ___) {
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'rule',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (flag) => ruleStore.get(flag);

      final client = createClient();
      final results = client.getTreatmentsByFlagSets(['set1']);

      expect(results, hasLength(2));
      expect(results, everyElement(equals('on')));
    });
  });

  group('SplitClient.getTreatmentsWithConfig', () {
    test('returns EvaluationResult for each flag', () {
      eventsManager.notifyReady();
      evaluator.evaluateHandler = (_, __, ___, ____) {
        return EngineEvaluationResult(
            treatment: 'on',
            label: 'rule',
            impressionDisabled: false,
            changeNumber: 0);
      };
      evaluator.getRuleHandler = (_) => makeSplit(
            configurations: {'on': '{"v":1}'},
          );

      final client = createClient();
      final results = client.getTreatmentsWithConfig(['a', 'b']);

      expect(results, hasLength(2));
      expect(results[0].treatment, equals('on'));
      expect(results[0].config, equals('{"v":1}'));
    });
  });

  group('SplitClient.track', () {
    test('returns false for empty eventType', () {
      final client = createClient();
      expect(client.track('', 'user'), isFalse);
    });

    test('returns true for valid eventType', () {
      final client = createClient();
      expect(client.track('purchase', 'user'), isTrue);
    });

    test('returns false when properties exceed 300 keys', () {
      final client = createClient();
      final bigProps = Map.fromEntries(
        List.generate(301, (i) => MapEntry('key_$i', i)),
      );
      expect(client.track('event', 'user', properties: bigProps), isFalse);
    });

    test('returns true when properties are within limit', () {
      final client = createClient();
      final props = {'item': 'shoes', 'price': 99.99};
      expect(client.track('purchase', 'user', properties: props), isTrue);
    });

    test('accepts value parameter', () {
      final client = createClient();
      expect(
        client.track('purchase', 'user', value: 19.99),
        isTrue,
      );
    });
  });

  group('SplitClient readiness — whenReady / whenTimeout / whenUpdated', () {
    test('whenReady completes when eventsManager notifies ready', () async {
      final client = createClient();
      final future = client.whenReady();
      eventsManager.notifyReady();
      await expectLater(future, completes);
    });

    test('whenReady is latched — subscribing after ready returns resolved future', () async {
      eventsManager.notifyReady();
      await expectLater(createClient().whenReady(), completes);
    });

    test('whenTimeout completes when eventsManager notifies timeout', () async {
      final client = createClient();
      final future = client.whenTimeout();
      eventsManager.notifyTimeout();
      await expectLater(future, completes);
    });

    test('whenUpdated emits changed flags', () async {
      final client = createClient();
      final received = <List<String>>[];
      final sub = client.whenUpdated().listen(received.add);
      eventsManager.notifyUpdate(['flag_a']);
      await Future.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received[0], equals(['flag_a']));
      await sub.cancel();
    });

    test('whenReady completes normally on destroy before ready', () async {
      final client = createClient();
      final future = client.whenReady();
      await eventsManager.dispose();
      await expectLater(future, completes);
    });
  });
}
