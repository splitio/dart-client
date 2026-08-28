import 'dart:async';

import 'package:splitio_commons/src/event_tracker/event.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/input_validation/attributes.dart';
import 'package:splitio_commons/src/input_validation/flag_name.dart';
import 'package:splitio_commons/src/input_validation/flag_names.dart';
import 'package:splitio_commons/src/input_validation/flag_set.dart';
import 'package:splitio_commons/src/input_validation/key.dart';
import 'package:splitio_commons/src/input_validation/operational.dart';
import 'package:splitio_commons/src/input_validation/event_properties.dart';
import 'package:splitio_commons/src/input_validation/event_type.dart';
import 'package:splitio_commons/src/input_validation/event_value.dart';
import 'package:splitio_commons/src/input_validation/traffic_type.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/evaluation_options.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/impression.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';

abstract class SplitClient {
  String getTreatment(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  List<String> getTreatments(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  List<String> getTreatmentsByFlagSets(List<String> flagSets,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});

  EvaluationResult getTreatmentWithConfig(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  List<EvaluationResult> getTreatmentsWithConfig(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  List<EvaluationResult> getTreatmentsWithConfigByFlagSets(
      List<String> flagSets,
      {Map<String, Object?>? attributes,
      EvaluationOptions? opts});

  bool track(String eventType, String trafficType,
      {double? value, Map<String, Object?>? properties});

  Future<void> whenReady();
  Future<void> whenTimeout();
  Stream<List<String>> whenUpdated();

  Future<void> flush();
  Future<void> destroy();
}

class SplitClientImpl implements SplitClient {
  final Key _key;
  final LocalEvaluator _evaluator;
  final ImpressionsManager _impressions;
  final EventsManager _eventsManager;
  final EventsTracker _eventsTracker;
  final InMemoryRuleStore _ruleStore;
  final SplitLogger _log;
  final Future<void> Function() _flushRecorders;
  bool _destroyed = false;

  SplitClientImpl({
    required Key key,
    required LocalEvaluator evaluator,
    required ImpressionsManager impressions,
    required EventsManager eventsManager,
    required EventsTracker eventsTracker,
    required InMemoryRuleStore ruleStore,
    required SplitLogger logger,
    required Future<void> Function() flushRecorders,
  })  : _key = key,
        _evaluator = evaluator,
        _impressions = impressions,
        _eventsManager = eventsManager,
        _eventsTracker = eventsTracker,
        _ruleStore = ruleStore,
        _log = logger,
        _flushRecorders = flushRecorders;

  @override
  String getTreatment(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    return _evaluate(flag,
            attributes: attributes, opts: opts, method: 'getTreatment')
        .treatment;
  }

  @override
  List<String> getTreatments(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    const method = 'getTreatments';
    final validated = validateFlagNames(flags, method);
    if (!validated.isValid) {
      _log.error(validated.error!);
      return <String>[];
    }
    if (validated.warning != null) _log.warning(validated.warning!);
    return validated.value!
        .map((f) =>
            _evaluate(f, attributes: attributes, opts: opts, method: method)
                .treatment)
        .toList();
  }

  @override
  List<String> getTreatmentsByFlagSets(List<String> flagSets,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    const method = 'getTreatmentsByFlagSets';
    final validated = validateFlagSets(flagSets, method);
    if (!validated.isValid) {
      _log.error(validated.error!);
      return <String>[];
    }
    if (validated.warning != null) _log.warning(validated.warning!);
    final splits = _ruleStore.getByFlagSets(validated.value!);
    return splits
        .map((s) => _evaluate(s.name,
                attributes: attributes, opts: opts, method: method)
            .treatment)
        .toList();
  }

  @override
  EvaluationResult getTreatmentWithConfig(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    return _evaluate(flag,
        attributes: attributes, opts: opts, method: 'getTreatmentWithConfig');
  }

  @override
  List<EvaluationResult> getTreatmentsWithConfig(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    const method = 'getTreatmentsWithConfig';
    final validated = validateFlagNames(flags, method);
    if (!validated.isValid) {
      _log.error(validated.error!);
      return <EvaluationResult>[];
    }
    if (validated.warning != null) _log.warning(validated.warning!);
    return validated.value!
        .map((f) =>
            _evaluate(f, attributes: attributes, opts: opts, method: method))
        .toList();
  }

  @override
  List<EvaluationResult> getTreatmentsWithConfigByFlagSets(
      List<String> flagSets,
      {Map<String, Object?>? attributes,
      EvaluationOptions? opts}) {
    const method = 'getTreatmentsWithConfigByFlagSets';
    final validated = validateFlagSets(flagSets, method);
    if (!validated.isValid) {
      _log.error(validated.error!);
      return <EvaluationResult>[];
    }
    if (validated.warning != null) _log.warning(validated.warning!);
    final splits = _ruleStore.getByFlagSets(validated.value!);
    return splits
        .map((s) => _evaluate(s.name,
            attributes: attributes, opts: opts, method: method))
        .toList();
  }

  @override
  bool track(String eventType, String trafficType,
      {double? value, Map<String, Object?>? properties}) {
    const method = 'track';
    if (_checkDestroyed(method)) return false;
    final destroyedGuard = validateIfNotDestroyed(
        isDestroyed: _eventsManager.isDestroyed, method: method);
    if (!destroyedGuard.isValid) {
      _log.error(destroyedGuard.error!);
      return false;
    }
    final keyGuard = validateKey(_key, method);
    if (!keyGuard.isValid) {
      _log.error(keyGuard.error!);
      return false;
    }
    if (!validateEventType(eventType)) {
      _log.error('$method: invalid event type "$eventType"');
      return false;
    }
    final ttResult = validateTrafficType(trafficType);
    if (ttResult == null) {
      _log.error('$method: invalid traffic type "$trafficType"');
      return false;
    }
    if (ttResult.wasLowercased) {
      _log.warning(
          '$method: trafficType "$trafficType" should be lowercase — normalized to "${ttResult.value}"');
    }
    if (_eventsManager.isReady &&
        !_ruleStore.trafficTypeExists(ttResult.value)) {
      _log.warning(
          '$method: trafficType "${ttResult.value}" is not associated with any flag');
    }
    if (!validateEventValue(value)) {
      _log.error(
          '$method: value must be a finite number for event "$eventType"');
      return false;
    }
    final validated = validateProperties(properties);
    if (validated == null) {
      _log.error('$method: invalid properties for event "$eventType"');
      return false;
    }

    final event = Event(
      eventTypeId: eventType,
      trafficTypeName: ttResult.value,
      key: _key.matchingKey,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      value: value,
      properties: validated.properties,
    );
    return _eventsTracker.track(event, validated.size);
  }

  @override
  Future<void> whenReady() => _eventsManager.onReady;

  @override
  Future<void> whenTimeout() => _eventsManager.onTimeout;

  @override
  Stream<List<String>> whenUpdated() => _eventsManager.onUpdated;

  @override
  Future<void> flush() {
    if (_destroyed) return Future.value();
    return _flushRecorders();
  }

  @override
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    await _flushRecorders();
  }

  /// Check if client is destroyed and log error if so.
  /// Returns true if destroyed (caller should return immediately).
  bool _checkDestroyed(String method) {
    if (_destroyed) {
      _log.error('$method: Client has already been destroyed - no calls possible');
      return true;
    }
    return false;
  }

  EvaluationResult _evaluate(String flag,
      {Map<String, Object?>? attributes,
      EvaluationOptions? opts,
      String method = 'getTreatment'}) {
    try {
      if (_checkDestroyed(method)) {
        return const EvaluationResult(treatment: 'control');
      }

      if (!_eventsManager.isReady) {
        _log.warning('$method: SDK not ready — returning control');
        return const EvaluationResult(treatment: 'control');
      }

      final destroyedGuard = validateIfNotDestroyed(
          isDestroyed: _eventsManager.isDestroyed, method: method);
      if (!destroyedGuard.isValid) {
        _log.error(destroyedGuard.error!);
        return const EvaluationResult(treatment: 'control');
      }

      final keyResult = validateKey(_key, method);
      if (!keyResult.isValid) {
        _log.error(keyResult.error!);
        return const EvaluationResult(treatment: 'control');
      }

      final flagResult = validateFlagName(flag, method);
      if (!flagResult.isValid) {
        _log.error(flagResult.error!);
        return const EvaluationResult(treatment: 'control');
      }
      if (flagResult.warning != null) _log.warning(flagResult.warning!);
      final flagName = flagResult.value!;

      // Attributes: only empty keys are dropped; values pass through for
      // engine coercion (spec §5).
      final attrsResult = validateAttributes(attributes, method);
      if (attrsResult.warning != null) _log.warning(attrsResult.warning!);
      final cleanAttributes = attrsResult.value;

      final matchingKey = _key.matchingKey;
      final bucketingKey = _key.bucketingKey;

      final engineResult = _evaluator.evaluate(
        matchingKey,
        bucketingKey,
        flagName,
        cleanAttributes ?? const {},
      );

      if (engineResult == null) {
        _log.warning(
            '$method: "$flagName" does not exist in this environment.');
        return const EvaluationResult(treatment: 'control');
      }

      _recordImpression(
        flag: flagName,
        treatment: engineResult.treatment,
        label: engineResult.label,
        changeNumber: engineResult.changeNumber,
        matchingKey: matchingKey,
        bucketingKey: bucketingKey,
        attributes: cleanAttributes,
        opts: opts,
        impressionsDisabled: engineResult.impressionDisabled,
      );

      return EvaluationResult(
        treatment: engineResult.treatment,
        config: engineResult.config,
      );
    } catch (_) {
      _log.error('$method: error evaluating flag "$flag"');
      return const EvaluationResult(treatment: 'control');
    }
  }

  void _recordImpression({
    required String flag,
    required String treatment,
    required String label,
    required int? changeNumber,
    required String matchingKey,
    required String? bucketingKey,
    required Map<String, Object?>? attributes,
    required EvaluationOptions? opts,
    required bool impressionsDisabled,
  }) {
    final keyImpression = KeyImpression(
      feature: flag,
      keyName: matchingKey,
      bucketingKey: bucketingKey,
      treatment: treatment,
      label: label,
      changeNumber: changeNumber ?? 0,
      time: DateTime.now().millisecondsSinceEpoch,
      properties: opts?.properties,
    );

    _impressions.record(
        keyImpression, impressionsDisabled, attributes ?? const {});
  }
}
