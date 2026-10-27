import 'package:splitio_commons/src/client/client_state.dart';
import 'package:splitio_commons/src/event_tracker/event.dart';
import 'package:splitio_commons/src/event_tracker/events_tracker.dart';
import 'package:splitio_commons/src/input_validation/event_properties.dart';
import 'package:splitio_commons/src/input_validation/event_type.dart';
import 'package:splitio_commons/src/input_validation/event_value.dart';
import 'package:splitio_commons/src/input_validation/key.dart';
import 'package:splitio_commons/src/input_validation/operational.dart';
import 'package:splitio_commons/src/input_validation/traffic_type.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';

/// Shared `track` pipeline for both flavors: validates the call, builds the
/// [Event] and hands it to the [EventsTracker]. Lifecycle state is read from
/// the caller's [ClientState] on every call. Never throws.
class TrackMethod {
  final EventsTracker _eventsTracker;
  final InMemoryRuleStore _ruleStore;
  final SplitLogger _log;

  TrackMethod({
    required EventsTracker eventsTracker,
    required InMemoryRuleStore ruleStore,
    required SplitLogger logger,
  })  : _eventsTracker = eventsTracker,
        _ruleStore = ruleStore,
        _log = logger;

  bool track(Key key, String eventType, String trafficType, ClientState state,
      {double? value, Map<String, Object?>? properties}) {
    const method = 'track';
    if (state.isClientDestroyed) {
      _log.error(
          '$method: Client has already been destroyed - no calls possible');
      return false;
    }
    final destroyedGuard = validateIfNotDestroyed(
        isDestroyed: state.isEventsDestroyed, method: method);
    if (!destroyedGuard.isValid) {
      _log.error(destroyedGuard.error!);
      return false;
    }
    final keyGuard = validateKey(key, method);
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
    if (state.isReady && !_ruleStore.trafficTypeExists(ttResult.value)) {
      _log.warning(
          '$method: trafficType "${ttResult.value}" is not associated with any flag');
    }
    if (!validateEventValue(value)) {
      _log.error(
          '$method: value must be a finite number for event "$eventType"');
      return false;
    }
    final validated =
        validateProperties(properties, method: method, onWarning: _log.warning);
    if (validated == null) {
      _log.error('$method: the maximum size allowed for the properties is '
          '32768 bytes, which was exceeded.');
      return false;
    }

    final event = Event(
      eventTypeId: eventType,
      trafficTypeName: ttResult.value,
      // The trimmed key from validateKey MUST be used, not the raw
      // (possibly untrimmed) matching key (spec §16).
      key: keyGuard.value!.matchingKey,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      value: value,
      properties: validated.properties,
    );
    return _eventsTracker.track(event, validated.size);
  }
}
