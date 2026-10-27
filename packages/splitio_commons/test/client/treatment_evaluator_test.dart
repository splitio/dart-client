import 'dart:async';

import 'package:splitio_commons/src/client/client_state.dart';
import 'package:splitio_commons/src/client/treatment_evaluator.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/impression.dart';
import 'package:splitio_commons/src/models/key.dart';
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
  EngineEvaluationResult? result;
  Object? toThrow;
  int calls = 0;
  String? lastMatchingKey;
  String? lastBucketingKey;

  @override
  EngineEvaluationResult? evaluate(String matchingKey, String? bucketingKey,
      String flagName, Map<String, Object?> attributes) {
    calls++;
    lastMatchingKey = matchingKey;
    lastBucketingKey = bucketingKey;
    if (toThrow != null) throw toThrow!;
    return result;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImpressions implements ImpressionsManager {
  final recorded = <KeyImpression>[];
  final disabledFlags = <bool>[];

  @override
  void record(KeyImpression impression, bool impressionsDisabled,
      Map<String, Object?>? attributes) {
    recorded.add(impression);
    disabledFlags.add(impressionsDisabled);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _hit = EngineEvaluationResult(
    treatment: 'on',
    label: 'default rule',
    impressionDisabled: false,
    changeNumber: 7,
    config: '{"a":1}');

void main() {
  late _FakeState state;
  late _FakeEvaluator evaluator;
  late _FakeImpressions impressions;
  late TreatmentEvaluator subject;
  late List<String> logs;

  setUp(() {
    state = _FakeState();
    evaluator = _FakeEvaluator()..result = _hit;
    impressions = _FakeImpressions();
    logs = [];
    subject = TreatmentEvaluator(
        evaluator: evaluator,
        impressions: impressions,
        logger: SplitLogger(level: LogLevel.verbose));
  });

  EvaluationResult run(Key key, String flag,
      {Map<String, Object?>? attributes}) {
    late EvaluationResult r;
    runZoned(
        () => r = subject.evaluate(key, flag, state,
            attributes: attributes, method: 'getTreatment'),
        zoneSpecification:
            ZoneSpecification(print: (_, __, ___, line) => logs.add(line)));
    return r;
  }

  const key = Key(matchingKey: 'user');

  test('returns the engine treatment and config and records an impression', () {
    final r = run(key, 'flag');
    expect(r.treatment, 'on');
    expect(r.config, '{"a":1}');
    expect(impressions.recorded.single.feature, 'flag');
    expect(impressions.recorded.single.label, 'default rule');
    expect(impressions.recorded.single.changeNumber, 7);
  });

  test('not ready: control, one "not ready" impression, evaluator skipped', () {
    state.isReady = false;
    final r = run(key, 'flag');
    expect(r.treatment, 'control');
    expect(evaluator.calls, 0);
    expect(impressions.recorded, hasLength(1));
    expect(impressions.recorded.single.label, 'not ready');
    expect(impressions.recorded.single.changeNumber, isNull);
    expect(impressions.disabledFlags.single, isFalse);
  });

  test('trimmed key is used for evaluation and impressions', () {
    run(const Key(matchingKey: '  user  ', bucketingKey: ' bkt '), 'flag');
    expect(evaluator.lastMatchingKey, 'user');
    expect(evaluator.lastBucketingKey, 'bkt');
    expect(impressions.recorded.single.keyName, 'user');
    expect(impressions.recorded.single.bucketingKey, 'bkt');
  });

  test('missing flag: control, WARNING, no impression', () {
    evaluator.result = null;
    final r = run(key, 'ghost');
    expect(r.treatment, 'control');
    expect(impressions.recorded, isEmpty);
    expect(
        logs,
        contains('[Split][WARNING] getTreatment: "ghost" does not exist in '
            'this environment.'));
  });

  test('exception in evaluation: control and ERROR, nothing escapes', () {
    evaluator.toThrow = StateError('boom');
    final r = run(key, 'flag');
    expect(r.treatment, 'control');
    expect(impressions.recorded, isEmpty);
    expect(
        logs.single,
        startsWith(
            '[Split][ERROR] getTreatment: error evaluating flag "flag"'));
  });

  test('client destroyed: control and ERROR without trailing period', () {
    state.isClientDestroyed = true;
    final r = run(key, 'flag');
    expect(r.treatment, 'control');
    expect(evaluator.calls, 0);
    expect(impressions.recorded, isEmpty);
    expect(logs.single,
        '[Split][ERROR] getTreatment: Client has already been destroyed - no calls possible');
  });

  test('events manager destroyed: control and ERROR from the second guard', () {
    state.isEventsDestroyed = true;
    final r = run(key, 'flag');
    expect(r.treatment, 'control');
    expect(evaluator.calls, 0);
    expect(logs.single, startsWith('[Split][ERROR] getTreatment:'));
    expect(logs.single, endsWith('no calls possible.'));
  });

  test('impressionsDisabled from the engine result is passed through', () {
    evaluator.result = const EngineEvaluationResult(
        treatment: 'on', label: 'x', impressionDisabled: true, changeNumber: 1);
    run(key, 'flag');
    expect(impressions.disabledFlags.single, isTrue);
  });
}
