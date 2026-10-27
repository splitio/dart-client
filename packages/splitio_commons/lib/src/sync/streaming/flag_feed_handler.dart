import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';

import '../fetchers/flags_fetcher.dart';
import 'flag_update_strategy.dart';
import 'notification_processor.dart';
import 'on_demand_fetch_coordinator.dart';

/// Routes flag-side [FeedUpdate]s (`SPLIT_UPDATE`, `SPLIT_KILL`,
/// `RB_SEGMENT_UPDATE`) to the [FlagUpdateStrategy] and performs whatever
/// network follow-up the outcome requires (spec §12.1): a full
/// `/splitChanges` fetch when in-place apply isn't safe, or — when applied in
/// place — an immediate segments refresh on server-side topology, so a
/// newly-referenced segment registered by the strategy's `onApplied`
/// callback doesn't sit empty until the next catch-up/reconnect.
///
/// Extracted out of [FeedUpdateRouter] (Tidy First structural split, no
/// behavior change to the pre-existing fetch-required path) to keep both
/// classes within the repo's LOC budget.
class FlagFeedHandler {
  final FlagsFetcher _flagsFetcher;
  final FlagUpdateStrategy _flagStrategy;
  final Future<bool> Function()? _allSegmentsFetcher;
  final OnDemandFetchCoordinator? _ffCoordinator;
  final OnDemandFetchCoordinator? _rbsCoordinator;
  final SplitLogger _log;

  /// [ffCoordinator]/[rbsCoordinator] are optional (spec §10.2): when
  /// present, a fetch-required `SPLIT_UPDATE`/`SPLIT_KILL`/`RB_SEGMENT_UPDATE`
  /// notification with a usable `changeNumber` is routed through the matching
  /// on-demand coordinator (retry+backoff+CDN-bypass) instead of a single
  /// unconditional fetch. When absent, or the payload carries no int
  /// `changeNumber`, behavior is unchanged: a single plain fetch.
  FlagFeedHandler({
    required FlagsFetcher flagsFetcher,
    required FlagUpdateStrategy flagStrategy,
    Future<bool> Function()? allSegmentsFetcher,
    OnDemandFetchCoordinator? ffCoordinator,
    OnDemandFetchCoordinator? rbsCoordinator,
    required SplitLogger logger,
  })  : _flagsFetcher = flagsFetcher,
        _flagStrategy = flagStrategy,
        _allSegmentsFetcher = allSegmentsFetcher,
        _ffCoordinator = ffCoordinator,
        _rbsCoordinator = rbsCoordinator,
        _log = logger;

  void route(FeedUpdate update) {
    // RB_SEGMENT_UPDATE: FlagUpdateStrategy only applies SPLIT_UPDATE and
    // SPLIT_KILL in place; every other type — including RB_SEGMENT_UPDATE —
    // hits its default branch and returns fetchRequired. In-place RBS apply
    // (decompression + rule-based-segment store mutation) is DEFERRED to a
    // later increment, so a full /splitChanges fetch is the correct safe
    // fallback for now. We short-circuit here rather than round-tripping
    // through the strategy to make the "always fetch" contract explicit.
    if (update.type == 'RB_SEGMENT_UPDATE') {
      if (_notifyCoordinator(_rbsCoordinator, update, 'RB_SEGMENT_UPDATE')) {
        return;
      }
      _log.debug('StreamingManager: ${update.type} → full flags fetch');
      unawaited(fetchFlags());
      return;
    }
    final result = _flagStrategy.handle(update);
    _log.debug('StreamingManager: ${update.type} → ${result.outcome.name}');
    if (result.outcome == FlagUpdateOutcome.fetchRequired) {
      if (_notifyCoordinator(_ffCoordinator, update, update.type)) return;
      unawaited(fetchFlags());
    } else {
      _fetchSegmentsRegisteredByInPlaceApply();
    }
  }

  /// Routes [update] to [coordinator] when both it and a usable int
  /// `changeNumber` are present. Returns whether it did so (false → caller
  /// MUST fall back to its own unconditional fetch).
  bool _notifyCoordinator(
    OnDemandFetchCoordinator? coordinator,
    FeedUpdate update,
    String label,
  ) {
    if (coordinator == null) return false;
    final changeNumber = update.payload['changeNumber'];
    if (changeNumber is! int) return false;
    _log.debug('StreamingManager: $label → on-demand fetch coordinator '
        '(cn=$changeNumber)');
    coordinator.notify(changeNumber);
    return true;
  }

  /// Shared `/splitChanges` fetch, also used by [FeedUpdateRouter.catchUp].
  Future<bool> fetchFlags() => _flagsFetcher.fetch().catchError((Object e) {
        _log.warning('StreamingManager: flags fetch failed: $e');
        return false;
      });

  /// After an in-place `SPLIT_UPDATE` apply, a newly-referenced segment may
  /// have just been registered via [FlagUpdateStrategy]'s `onApplied`
  /// callback (the same side effect a fetched change performs) — but never
  /// actually fetched. On server-side topology the segments poll timer is
  /// stopped while push is up (`SyncManager.onStreamingUp()`), so
  /// without this it would stay empty until the next catch-up/reconnect.
  /// No-op on client-side (no [_allSegmentsFetcher] wired).
  void _fetchSegmentsRegisteredByInPlaceApply() {
    final allSegmentsFetcher = _allSegmentsFetcher;
    if (allSegmentsFetcher == null) return;
    unawaited(allSegmentsFetcher().catchError((Object e) {
      _log.warning('StreamingManager: in-place segments fetch failed: $e');
      return false;
    }));
  }

  /// Cancels [_ffCoordinator]/[_rbsCoordinator]'s pending retry timers, if
  /// wired. MUST be called by the owner on stop/destroy.
  void dispose() {
    _ffCoordinator?.dispose();
    _rbsCoordinator?.dispose();
  }
}
