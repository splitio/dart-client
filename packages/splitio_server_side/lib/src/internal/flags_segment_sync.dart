import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';

import 'referenced_segments.dart';

/// Keeps [SegmentStore] registration in sync with the current rule set
/// after every flags change — a fetched `/splitChanges` diff or an
/// in-place streaming apply — and, when that registration exposes a
/// segment the store has never actually fetched, triggers an immediate
/// `/segmentChanges` fetch instead of waiting for the next segments
/// polling interval (spec §8.2).
///
/// Closes a QA-reported READY-latency gap: `PollingManagerSS` starts the
/// flags and segments poll timers at the same instant, so a segment first
/// referenced by a flags fetch that lands between segments ticks would
/// otherwise sit unfetched — and READY withheld — until the segments
/// timer's own, independently-scheduled, next fire (which may be minutes
/// away). Calling [onFlagsChanged] removes that wait: the fetch happens as
/// soon as the new reference is known, regardless of either timer's phase.
class FlagsSegmentSync {
  final Store<ParsedSplit> _ruleStore;
  final SegmentStore _segmentStore;
  final Future<bool> Function() _fetchSegments;
  final SplitLogger _log;
  bool _destroyed = false;

  FlagsSegmentSync({
    required Store<ParsedSplit> ruleStore,
    required SegmentStore segmentStore,
    required Future<bool> Function() fetchSegments,
    required SplitLogger logger,
  })  : _ruleStore = ruleStore,
        _segmentStore = segmentStore,
        _fetchSegments = fetchSegments,
        _log = logger;

  /// Re-scans the whole rule store for segment references (additive-only —
  /// existing members/cursors are preserved) and immediately fetches
  /// `/segmentChanges` when that scan registered at least one segment name
  /// the store didn't already know about. A no-op, fetch-wise, when
  /// nothing new was registered — the periodic segments poll (or a prior
  /// in-flight trigger from an earlier call) already owns catching those
  /// up, so this never double-fetches on a flags change that doesn't touch
  /// segment references.
  void onFlagsChanged() {
    if (_destroyed) return;
    final before = _segmentStore.getRegisteredSegments().toSet();
    final referenced = referencedSegmentsIn(_ruleStore.getAll());
    _segmentStore.registerSegments(referenced);
    final registeredSomethingNew =
        referenced.any((name) => !before.contains(name));
    if (!registeredSomethingNew) return;
    // _fetchSegments is the shared SegmentChangesFetcher.fetch() — the same
    // method PollingManagerSS's initial sync/polling and (when enabled)
    // StreamingManager's catch-up already call. Its own in-flight guard is
    // what prevents this from duplicating a fetch those callers already
    // have running for the same newly-registered segment; nothing further
    // is needed here beyond not firing after destroy.
    unawaited(_fetchSegments().catchError((Object e) {
      _log.warning('FlagsSegmentSync: immediate segments fetch failed: $e');
      return false;
    }));
  }

  /// Marks this sync destroyed. After this, [onFlagsChanged] is a no-op —
  /// called from [ServerDependencyContainer.dispose] so a flags change that
  /// lands after the factory has been torn down can never start a new
  /// segments fetch. Idempotent.
  void destroy() {
    _destroyed = true;
  }
}
