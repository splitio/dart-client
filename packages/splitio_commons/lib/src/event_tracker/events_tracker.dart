import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';

import 'event.dart';
import 'events_store.dart';

class EventsTracker {
  final EventsStore _store;
  final ConsentStatus Function() _consentProvider;
  final SplitLogger _log;

  EventsTracker({
    required EventsStore store,
    required ConsentStatus Function() consentProvider,
    required SplitLogger log,
  })  : _store = store,
        _consentProvider = consentProvider,
        _log = log;

  bool track(Event event, int size) {
    if (_consentProvider() == ConsentStatus.declined) return false;

    _store.push(event, size);
    _log.info(
        'Event "${event.eventTypeId}" queued for traffic type "${event.trafficTypeName}"');
    return true;
  }
}
