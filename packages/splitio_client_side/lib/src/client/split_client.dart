import 'dart:async';

import 'package:splitio_commons/src/client/basic_split_client.dart';
import 'package:splitio_commons/src/client/client_state.dart';
import 'package:splitio_commons/src/client/track_method.dart';
import 'package:splitio_commons/src/client/treatment_evaluator.dart';
import 'package:splitio_commons/src/client/treatment_methods.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/events/client_updates.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/local/local_evaluator.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/evaluation_options.dart';
import 'package:splitio_commons/src/models/evaluation_result.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/impressions/impressions_manager.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';

abstract class SplitClient implements BasicSplitClient {
  String getTreatment(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  Map<String, String> getTreatments(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  Map<String, String> getTreatmentsByFlagSets(List<String> flagSets,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});

  EvaluationResult getTreatmentWithConfig(String flag,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  Map<String, EvaluationResult> getTreatmentsWithConfig(List<String> flags,
      {Map<String, Object?>? attributes, EvaluationOptions? opts});
  Map<String, EvaluationResult> getTreatmentsWithConfigByFlagSets(
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

class SplitClientImpl implements SplitClient, ClientState {
  final Key _key;
  final TreatmentMethods _methods;
  final EventsManager _eventsManager;
  final TrackMethod _track;
  final Future<void> Function() _flushRecorders;
  final Future<void> Function()? _onDestroyed;
  bool _destroyed = false;
  late final ClientUpdates _updates = ClientUpdates(_eventsManager.onUpdated);

  SplitClientImpl({
    required Key key,
    required LocalEvaluator evaluator,
    required ImpressionsManager impressions,
    required EventsManager eventsManager,
    required EventsTracker eventsTracker,
    required InMemoryRuleStore ruleStore,
    required SplitLogger logger,
    required Future<void> Function() flushRecorders,
    Future<void> Function()? onDestroyed,
  })  : _key = key,
        _methods = TreatmentMethods(
            evaluator: TreatmentEvaluator(
                evaluator: evaluator, impressions: impressions, logger: logger),
            ruleStore: ruleStore,
            logger: logger),
        _eventsManager = eventsManager,
        _track = TrackMethod(
            eventsTracker: eventsTracker, ruleStore: ruleStore, logger: logger),
        _flushRecorders = flushRecorders,
        _onDestroyed = onDestroyed;

  @override
  String getTreatment(String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _methods
          .treatment(_key, flag, this,
              attributes: attributes, opts: opts, method: 'getTreatment')
          .treatment;

  @override
  Map<String, String> getTreatments(List<String> flags,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _toTreatments(_methods.treatments(_key, flags, this,
          attributes: attributes, opts: opts, method: 'getTreatments'));

  @override
  Map<String, String> getTreatmentsByFlagSets(List<String> flagSets,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _toTreatments(_methods.treatmentsByFlagSets(_key, flagSets, this,
          attributes: attributes,
          opts: opts,
          method: 'getTreatmentsByFlagSets'));

  @override
  EvaluationResult getTreatmentWithConfig(String flag,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _methods.treatment(_key, flag, this,
          attributes: attributes, opts: opts, method: 'getTreatmentWithConfig');

  @override
  Map<String, EvaluationResult> getTreatmentsWithConfig(List<String> flags,
          {Map<String, Object?>? attributes, EvaluationOptions? opts}) =>
      _methods.treatments(_key, flags, this,
          attributes: attributes,
          opts: opts,
          method: 'getTreatmentsWithConfig');

  @override
  Map<String, EvaluationResult> getTreatmentsWithConfigByFlagSets(
          List<String> flagSets,
          {Map<String, Object?>? attributes,
          EvaluationOptions? opts}) =>
      _methods.treatmentsByFlagSets(_key, flagSets, this,
          attributes: attributes,
          opts: opts,
          method: 'getTreatmentsWithConfigByFlagSets');

  static Map<String, String> _toTreatments(Map<String, EvaluationResult> r) =>
      {for (final e in r.entries) e.key: e.value.treatment};

  @override
  bool track(String eventType, String trafficType,
          {double? value, Map<String, Object?>? properties}) =>
      _track.track(_key, eventType, trafficType, this,
          value: value, properties: properties);

  @override
  bool get isClientDestroyed => _destroyed;

  @override
  bool get isEventsDestroyed => _eventsManager.isDestroyed;

  @override
  bool get isReady => _eventsManager.isReady;

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
    // Lets the owner release this client's readiness state (timers, its
    // EventsManager) without touching any other client (spec §8.5).
    await _onDestroyed?.call();
    await _flushRecorders();
  }
}
