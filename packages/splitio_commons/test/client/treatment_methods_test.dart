import 'dart:async';

import 'package:splitio_commons/src/client/client_state.dart';
import 'package:splitio_commons/src/client/treatment_evaluator.dart';
import 'package:splitio_commons/src/client/treatment_methods.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';
import 'package:splitio_commons/src/storage/store.dart';
import 'package:test/test.dart';

class _FakeState implements ClientState {
  @override
  bool isClientDestroyed = false;
  @override
  bool isEventsDestroyed = false;
  @override
  bool isReady = true;
}

class _FakeEvaluator implements LocalEvaluator {
  int calls = 0;

  @override
  EngineEvaluationResult? evaluate(String matchingKey, String? bucketingKey,
      String flagName, Map<String, Object?> attributes) {
    calls++;
    return const EngineEvaluationResult(
        treatment: 'on',
        label: 'default rule',
        impressionDisabled: false,
        changeNumber: 7,
        config: '{"a":1}');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImpressions implements ImpressionsManager {
  final recorded = <KeyImpression>[];

  @override
  void record(KeyImpression impression, bool impressionsDisabled,
      Map<String, Object?>? attributes) {
    recorded.add(impression);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ParsedSplit _split(String name, List<String> sets) => ParsedSplit(
      name: name,
      trafficTypeName: 'user',
      killed: false,
      defaultTreatment: 'off',
      conditions: const [],
      trafficAllocation: 100,
      seed: 1,
      algo: 2,
      changeNumber: 1,
      sets: sets,
    );

void main() {
  late _FakeState state;
  late _FakeEvaluator evaluator;
  late _FakeImpressions impressions;
  late TreatmentMethods subject;
  late List<String> logs;

  const key = Key(matchingKey: 'user');
  const notReadyWarning = 'the SDK is not ready';

  setUp(() {
    state = _FakeState();
    evaluator = _FakeEvaluator();
    impressions = _FakeImpressions();
    logs = [];
    final ruleStore = InMemoryRuleStore()
      ..applyChange(Change(changeNumber: 1, updates: {
        'a': _split('a', ['s1']),
        'b': _split('b', ['s1']),
        'c': _split('c', ['s2']),
      }));
    final logger = SplitLogger(level: LogLevel.verbose);
    subject = TreatmentMethods(
        evaluator: TreatmentEvaluator(
            evaluator: evaluator, impressions: impressions, logger: logger),
        ruleStore: ruleStore,
        logger: logger);
  });

  T capture<T>(T Function() body) {
    late T r;
    runZoned(() => r = body(),
        zoneSpecification:
            ZoneSpecification(print: (_, __, ___, line) => logs.add(line)));
    return r;
  }

  int count(String needle) => logs.where((l) => l.contains(needle)).length;

  group('happy paths', () {
    test('treatment returns the engine result', () {
      final r = capture(() =>
          subject.treatment(key, 'a', state, method: 'getTreatmentWithConfig'));
      expect(r.treatment, 'on');
      expect(r.config, '{"a":1}');
      expect(impressions.recorded.single.feature, 'a');
    });

    test('treatments evaluates every listed flag', () {
      final r = capture(() =>
          subject.treatments(key, ['a', 'b'], state, method: 'getTreatments'));
      expect(r.keys, ['a', 'b']);
      expect(r.values.map((e) => e.treatment), ['on', 'on']);
      expect(impressions.recorded, hasLength(2));
    });

    test('treatmentsByFlagSets evaluates only flags in the sets', () {
      final r = capture(() => subject.treatmentsByFlagSets(key, ['s1'], state,
          method: 'getTreatmentsByFlagSets'));
      expect(r.keys.toSet(), {'a', 'b'});
      expect(impressions.recorded, hasLength(2));
    });
  });

  group('before READY', () {
    setUp(() => state.isReady = false);

    test('treatment: control, one "not ready" impression, one warning', () {
      final r = capture(
          () => subject.treatment(key, 'a', state, method: 'getTreatment'));
      expect(r.treatment, 'control');
      expect(evaluator.calls, 0);
      expect(impressions.recorded.single.label, 'not ready');
      expect(count(notReadyWarning), 1);
    });

    test('treatments: control per flag, impression per flag, one warning', () {
      final r = capture(() =>
          subject.treatments(key, ['a', 'b'], state, method: 'getTreatments'));
      expect(r.values.map((e) => e.treatment), ['control', 'control']);
      expect(
          impressions.recorded.map((i) => i.label), ['not ready', 'not ready']);
      expect(count(notReadyWarning), 1);
    });

    test('treatmentsByFlagSets: returns {} and records nothing', () {
      final r = capture(() => subject.treatmentsByFlagSets(key, ['s1'], state,
          method: 'getTreatmentsByFlagSets'));
      expect(r, isEmpty);
      expect(impressions.recorded, isEmpty);
      expect(evaluator.calls, 0);
      expect(count(notReadyWarning), 1);
    });
  });

  group('list validation', () {
    test('an invalid flag in a list logs at ERROR and valid ones evaluate', () {
      final r = capture(() =>
          subject.treatments(key, ['a', ''], state, method: 'getTreatments'));
      expect(r.keys, ['a']);
      expect(logs.where((l) => l.contains('ERROR')), isNotEmpty);
    });

    test('an invalid list returns {} and logs at ERROR', () {
      final r = capture(
          () => subject.treatments(key, [], state, method: 'getTreatments'));
      expect(r, isEmpty);
      expect(logs.where((l) => l.contains('ERROR')), isNotEmpty);
      expect(impressions.recorded, isEmpty);
    });

    test('invalid flag sets return {} and log at ERROR', () {
      final r = capture(() => subject.treatmentsByFlagSets(key, [], state,
          method: 'getTreatmentsByFlagSets'));
      expect(r, isEmpty);
      expect(logs.where((l) => l.contains('ERROR')), isNotEmpty);
    });
  });

  group('key guard in flag-set variants', () {
    test('an invalid key returns {} and logs the invalid-key ERROR', () {
      final r = capture(() => subject.treatmentsByFlagSets(
          const Key(matchingKey: ''), ['s1'], state,
          method: 'getTreatmentsByFlagSets'));
      expect(r, isEmpty);
      expect(count('you passed an empty key'), 1);
      expect(evaluator.calls, 0);
      expect(impressions.recorded, isEmpty);
    });

    test('a valid key logs nothing extra', () {
      capture(() => subject.treatmentsByFlagSets(key, ['s1'], state,
          method: 'getTreatmentsByFlagSets'));
      expect(count('key'), 0);
    });
  });
}
