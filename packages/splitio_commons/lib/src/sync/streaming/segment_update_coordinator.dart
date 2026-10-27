import 'package:splitio_commons/src/logger/logger.dart';

import 'clock.dart';
import 'on_demand_fetch_coordinator.dart';

/// Lazily creates one [OnDemandFetchCoordinator] per segment name for
/// server-side `SEGMENT_UPDATE` notifications (spec §10.2) — each segment
/// has its own independent cursor, so a notification for one segment MUST
/// NOT affect another's chase.
class SegmentUpdateCoordinator {
  final Future<bool> Function(String segmentName, {bool noCache, int? till})
      _fetcher;
  final int Function(String segmentName) _cursor;
  final Scheduler _scheduler;
  final SplitLogger _log;
  final Map<String, OnDemandFetchCoordinator> _coordinators = {};

  SegmentUpdateCoordinator({
    required Future<bool> Function(String segmentName,
            {bool noCache, int? till})
        fetcher,
    required int Function(String segmentName) cursor,
    required Scheduler scheduler,
    required SplitLogger logger,
  })  : _fetcher = fetcher,
        _cursor = cursor,
        _scheduler = scheduler,
        _log = logger;

  /// Routes a `SEGMENT_UPDATE` notification for [segmentName] to that
  /// segment's own coordinator, creating it on first use.
  void notify(String segmentName, int changeNumber) {
    final coordinator = _coordinators.putIfAbsent(
      segmentName,
      () => OnDemandFetchCoordinator(
        cursor: () => _cursor(segmentName),
        fetch: ({bool noCache = false, int? till}) =>
            _fetcher(segmentName, noCache: noCache, till: till),
        scheduler: _scheduler,
        logger: _log,
        name: 'SegmentUpdateCoordinator[$segmentName]',
      ),
    );
    coordinator.notify(changeNumber);
  }

  /// Cancels every tracked segment's pending timer. MUST be called on
  /// stop/destroy so no timer outlives the streaming manager.
  void dispose() {
    for (final c in _coordinators.values) {
      c.dispose();
    }
  }
}
