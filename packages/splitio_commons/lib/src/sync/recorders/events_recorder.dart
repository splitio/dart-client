import 'dart:async';

import 'package:splitio_commons/src/event_tracker/event_tracker.dart';
import 'package:splitio_commons/src/sync/sync.dart';

import 'batch_submitter.dart';

class EventsRecorder extends Recorder {
  static const int _batchSize = 500;

  final EventsStore _store;
  final BatchSubmitter<Event> _submitter;

  EventsRecorder({
    required EventsStore store,
    required super.httpClient,
    required super.url,
    required super.pushRateSeconds,
    required super.log,
  })  : _store = store,
        _submitter = BatchSubmitter(log: log, dataTypeName: 'events');

  @override
  void clearRetained() => _submitter.clear();

  @override
  Future<void> flush() async {
    final events = _submitter.prependRetained(_store.popAll());
    if (events.isEmpty) return;

    for (var i = 0; i < events.length; i += _batchSize) {
      final end =
          i + _batchSize > events.length ? events.length : i + _batchSize;
      final batch = events.sublist(i, end);
      await _submitter.submit(
        batch,
        () => httpClient.post(
          '$url/events/bulk',
          body: batch.map((e) => e.toJson()).toList(),
        ),
      );
    }
  }
}
