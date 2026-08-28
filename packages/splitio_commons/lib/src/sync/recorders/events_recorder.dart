import 'dart:async';

import 'package:splitio_commons/src/event_tracker/event_tracker.dart';
import 'package:splitio_commons/src/sync/sync.dart';

class EventsRecorder extends Recorder {
  static const int _batchSize = 500;

  final EventsStore _store;

  EventsRecorder({
    required EventsStore store,
    required super.httpClient,
    required super.url,
    required super.pushRateSeconds,
    required super.log,
  }) : _store = store;

  @override
  Future<void> flush() async {
    final events = _store.popAll();
    if (events.isEmpty) return;

    for (var i = 0; i < events.length; i += _batchSize) {
      final end =
          i + _batchSize > events.length ? events.length : i + _batchSize;
      final batch = events.sublist(i, end);
      final payload = batch.map((e) => e.toJson()).toList();
      try {
        await httpClient.post('$url/events/bulk', body: payload);
      } catch (e) {
        log.error('Failed to post events batch: $e');
      }
    }
  }
}
