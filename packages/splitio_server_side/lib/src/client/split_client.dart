import 'dart:async';

import 'package:splitio_commons/src/client/basic_split_client.dart';
import 'package:splitio_commons/src/client/client_state.dart';
import 'package:splitio_commons/src/client/track_method.dart';
import 'package:splitio_commons/src/client/treatment_evaluator.dart';
import 'package:splitio_commons/src/client/treatment_methods.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/events/client_updates.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/input_validation/flag_names.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/evaluation_options.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';

export 'package:splitio_commons/src/client/basic_split_client.dart'
    show BasicSplitClient;

/// Normalizes a key argument (either [String] or [Key]) into matching +
/// bucketing keys. Any other type (e.g. a `Map` or a custom domain object)
/// is NOT a `Key`/`String` and MUST NOT throw through the SDK boundary: it
/// is mapped to an empty matching key, which routes it through the exact
/// same `validateKey()` check (see `input_validation/key.dart`) that an
/// empty String key already goes through today. That check logs an error
/// and the caller fails open — treatment methods return `'control'`, `track`
/// returns `false` — never a thrown exception.
(String, String?) _asKey(Object key) {
  if (key is Key) return (key.matchingKey, key.bucketingKey);
  if (key is String) return (key, null);
  return ('', null);
}

/// Public SS client contract. Adds treatment/track methods (with the
/// user key passed positionally per call) on top of the shared
/// lifecycle surface from commons. `SplitFactory.client()` returns this
/// type — both the real [SplitClientImpl] and the NoOp variant
/// implement it.
///
/// The `key` parameter of every method below MUST be a [String] or a [Key].
/// Any other type (e.g. a `Map` or a custom domain object) is logged as an
/// invalid key and the call fails open instead of throwing: treatment
/// methods return `'control'` (multi-flag variants return a `Map` with
/// `'control'` per valid flag name; `ByFlagSets` variants return an empty
/// map), and `track` returns `false`.
abstract class ServerSplitClient implements BasicSplitClient {
  String getTreatment(Object key, String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  Map<String, String> getTreatments(Object key, List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  Map<String, String> getTreatmentsByFlagSets(Object key, List<String> flagSets,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  EvaluationResult getTreatmentWithConfig(Object key, String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  Map<String, EvaluationResult> getTreatmentsWithConfig(
      Object key, List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  Map<String, EvaluationResult> getTreatmentsWithConfigByFlagSets(
      Object key, List<String> flagSets,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  bool track(Object key, String trafficType, String eventType,
      {double? value, Map<String, Object?>? properties});
}

/// Server-side `SplitClient` implementation. Single-tenant: the factory
/// holds one instance for its lifetime, and every treatment/track call
/// takes the user key positionally.
class SplitClientImpl implements ServerSplitClient, ClientState {
  final EventsManager _eventsManager;
  final TrackMethod _track;
  final Future<void> Function() _flushRecorders;
  final TreatmentMethods _methods;
  bool _destroyed = false;
  late final ClientUpdates _updates = ClientUpdates(_eventsManager.onUpdated);

  SplitClientImpl({
    required LocalEvaluator evaluator,
    required ImpressionsManager impressions,
    required EventsManager eventsManager,
    required EventsTracker eventsTracker,
    required InMemoryRuleStore ruleStore,
    required SplitLogger logger,
    required Future<void> Function() flushRecorders,
  })  : _eventsManager = eventsManager,
        _track = TrackMethod(
            eventsTracker: eventsTracker, ruleStore: ruleStore, logger: logger),
        _flushRecorders = flushRecorders,
        _methods = TreatmentMethods(
            evaluator: TreatmentEvaluator(
                evaluator: evaluator, impressions: impressions, logger: logger),
            ruleStore: ruleStore,
            logger: logger);

  @override
  String getTreatment(Object key, String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _methods
          .treatment(_toKey(key), flag, this,
              attributes: attributes, opts: opts, method: 'getTreatment')
          .treatment;

  @override
  Map<String, String> getTreatments(Object key, List<String> flags,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _toTreatments(_methods.treatments(_toKey(key), flags, this,
          attributes: attributes, opts: opts, method: 'getTreatments'));

  @override
  Map<String, String> getTreatmentsByFlagSets(Object key, List<String> flagSets,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _toTreatments(_methods.treatmentsByFlagSets(_toKey(key), flagSets, this,
          attributes: attributes,
          opts: opts,
          method: 'getTreatmentsByFlagSets'));

  @override
  EvaluationResult getTreatmentWithConfig(Object key, String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _methods.treatment(_toKey(key), flag, this,
          attributes: attributes, opts: opts, method: 'getTreatmentWithConfig');

  @override
  Map<String, EvaluationResult> getTreatmentsWithConfig(
          Object key, List<String> flags,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _methods.treatments(_toKey(key), flags, this,
          attributes: attributes,
          opts: opts,
          method: 'getTreatmentsWithConfig');

  @override
  Map<String, EvaluationResult> getTreatmentsWithConfigByFlagSets(
          Object key, List<String> flagSets,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _methods.treatmentsByFlagSets(_toKey(key), flagSets, this,
          attributes: attributes,
          opts: opts,
          method: 'getTreatmentsWithConfigByFlagSets');

  static Key _toKey(Object key) {
    final (matchingKey, bucketingKey) = _asKey(key);
    return Key(matchingKey: matchingKey, bucketingKey: bucketingKey);
  }

  static Map<String, String> _toTreatments(Map<String, EvaluationResult> r) =>
      {for (final e in r.entries) e.key: e.value.treatment};

  @override
  bool get isClientDestroyed => _destroyed;

  @override
  bool get isEventsDestroyed => _eventsManager.isDestroyed;

  @override
  bool get isReady => _eventsManager.isReady;

  @override
  bool track(Object key, String trafficType, String eventType,
      {double? value, Map<String, Object?>? properties}) {
    final (matchingKey, _) = _asKey(key);
    return _track.track(
        Key(matchingKey: matchingKey), eventType, trafficType, this,
        value: value, properties: properties);
  }

  @override
  Future<void> whenReady() => _eventsManager.onReady;

  @override
  Future<void> whenTimeout() => _eventsManager.onTimeout;

  @override
  Stream<List<String>> whenUpdated() => _updates.stream;

  @override
  Future<void> flush() {
    if (_destroyed) return Future.value();
    return _flushRecorders();
  }

  @override
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    await _updates.close();
    await _flushRecorders();
  }
}

class _NoOpSplitClient implements ServerSplitClient {
  final EventsManager _eventsManager;

  _NoOpSplitClient(this._eventsManager);

  @override
  String getTreatment(Object key, String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      'control';

  @override
  Map<String, String> getTreatments(Object key, List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    final validated = validateFlagNames(flags, 'getTreatments');
    if (!validated.isValid) return <String, String>{};
    return {for (final f in validated.value!) f: 'control'};
  }

  @override
  Map<String, String> getTreatmentsByFlagSets(Object key, List<String> flagSets,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      const <String, String>{};

  @override
  EvaluationResult getTreatmentWithConfig(Object key, String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      const EvaluationResult(treatment: 'control');

  @override
  Map<String, EvaluationResult> getTreatmentsWithConfig(
      Object key, List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts}) {
    final validated = validateFlagNames(flags, 'getTreatmentsWithConfig');
    if (!validated.isValid) return <String, EvaluationResult>{};
    return {
      for (final f in validated.value!)
        f: const EvaluationResult(treatment: 'control')
    };
  }

  @override
  Map<String, EvaluationResult> getTreatmentsWithConfigByFlagSets(
          Object key, List<String> flagSets,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      const <String, EvaluationResult>{};

  @override
  bool track(Object key, String trafficType, String eventType,
          {double? value, Map<String, Object?>? properties}) =>
      false;

  // A NoOp client's whenReady() MUST NOT complete — the invalid SDK key
  // MUST surface as a startup failure, not look like a ready SDK (spec §7).
  @override
  Future<void> whenReady() => _eventsManager.onReady;

  // MUST complete after readyTimeout elapses (armed by the owning
  // _NoOpSplitFactory), not instantly and not never (spec §7, §8.2).
  @override
  Future<void> whenTimeout() => _eventsManager.onTimeout;

  @override
  Stream<List<String>> whenUpdated() => const Stream.empty();

  @override
  Future<void> flush() async {}

  @override
  Future<void> destroy() async {}
}

/// Public accessor for the NoOp client returned by `_NoOpSplitFactory`.
/// Kept as a top-level function so the private class stays private.
/// [eventsManager] backs `whenReady()`/`whenTimeout()`; the factory arms its
/// readyTimeout timer against the same instance.
ServerSplitClient noOpServerSplitClient(EventsManager eventsManager) =>
    _NoOpSplitClient(eventsManager);
