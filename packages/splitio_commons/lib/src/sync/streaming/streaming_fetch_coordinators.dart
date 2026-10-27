import 'package:splitio_commons/src/logger/logger.dart';

import 'clock.dart';
import 'on_demand_fetch_coordinator.dart';
import 'segment_update_coordinator.dart';

/// The three on-demand fetch coordinators [StreamingManager] wires into its
/// [FeedUpdateRouter] (spec §10.2): one chasing the `ff` cursor
/// (`SPLIT_UPDATE`/`SPLIT_KILL`), one chasing `rbs` (`RB_SEGMENT_UPDATE`,
/// via the same `/splitChanges` fetch), and — only on server-side topology,
/// when both [segmentFetcherWithOptions] and [segmentCursor] are supplied —
/// a lazily-per-segment-name one for `SEGMENT_UPDATE`.
typedef StreamingFetchCoordinators = ({
  OnDemandFetchCoordinator ff,
  OnDemandFetchCoordinator rbs,
  SegmentUpdateCoordinator? segment,
});

/// Builds a [StreamingFetchCoordinators] bundle. Extracted out of
/// [StreamingManager]'s constructor (Tidy First structural split) to keep
/// that class within the repo's LOC budget — this is plain, low-branching
/// wiring, not a class of its own.
StreamingFetchCoordinators buildOnDemandCoordinators({
  required int Function() ffCursor,
  required int Function() rbsCursor,
  required Future<bool> Function({bool noCache, int? till}) flagsFetch,
  required Scheduler scheduler,
  required SplitLogger logger,
  Future<bool> Function(String segmentName, {bool noCache, int? till})?
      segmentFetcherWithOptions,
  int Function(String segmentName)? segmentCursor,
}) {
  final ff = OnDemandFetchCoordinator(
    cursor: ffCursor,
    fetch: flagsFetch,
    scheduler: scheduler,
    logger: logger,
    name: 'OnDemandFetchCoordinator[ff]',
  );
  final rbs = OnDemandFetchCoordinator(
    cursor: rbsCursor,
    fetch: flagsFetch,
    scheduler: scheduler,
    logger: logger,
    name: 'OnDemandFetchCoordinator[rbs]',
  );
  final segment = (segmentFetcherWithOptions != null && segmentCursor != null)
      ? SegmentUpdateCoordinator(
          fetcher: segmentFetcherWithOptions,
          cursor: segmentCursor,
          scheduler: scheduler,
          logger: logger,
        )
      : null;
  return (ff: ff, rbs: rbs, segment: segment);
}
