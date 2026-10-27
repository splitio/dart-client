import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';

import '../fetchers/flags_fetcher.dart';
import '../fetchers/memberships_fetcher.dart';
import 'clock.dart';
import 'event_source_client.dart';
import 'flag_feed_handler.dart';
import 'flag_update_strategy.dart';
import 'membership_feed_dispatcher.dart';
import 'membership_update_strategy.dart';
import 'notification_processor.dart';
import 'on_demand_fetch_coordinator.dart';
import 'segment_update_coordinator.dart';
import 'streaming_event.dart';
import 'sync_delay_calculator.dart';

/// Ingests incoming SSE frames and routes data-bearing [FeedUpdate]s to the
/// flag/membership strategies, triggering the resulting fetches (spec §12).
///
/// A raw frame is categorized by the [NotificationProcessor]: control/occupancy/
/// error frames drive the FSM back through the injected [apply] callback, while
/// data updates dispatch here. Flag updates that cannot be applied in place fall
/// back to a full `/splitChanges` fetch; membership updates dispatch per
/// matching key, applying seed-based jitter (§12.3) to unbounded/bounded fetch
/// notifications via the injected [SyncDelayCalculator] + [Scheduler]. All
/// fetches are fire-and-forget with swallowed errors so a bad update never kills
/// streaming.
class FeedUpdateRouter {
  final Future<bool> Function(String segmentName)? _segmentFetcher;
  final Future<bool> Function()? _allSegmentsFetcher;
  final SegmentUpdateCoordinator? _segmentCoordinator;
  final FlagFeedHandler _flagHandler;
  final MembershipFeedDispatcher _membershipDispatcher;
  final NotificationProcessor _notificationProcessor;
  final Future<void> Function(StreamingEvent event) _apply;
  final SplitLogger _log;

  /// [membershipsFetcher] and [membershipStrategy] are optional: when absent
  /// (server-side topology, spec §17.2 Axis 3), MEMBERSHIPS_MS/LS_UPDATE frames
  /// are ignored and catch-up skips the memberships fetch — mirroring
  /// `javascript-commons` `pushManager.ts`, which only subscribes the membership
  /// handlers when a `userKey` is bound.
  ///
  /// [segmentFetcher] is optional and only wired on server-side topology: it
  /// takes a segment name and refreshes that single segment's membership store.
  /// When absent (client-side), `SEGMENT_UPDATE` frames are ignored — the
  /// symmetric partner of MEMBERSHIPS_* being ignored on server-side.
  ///
  /// [allSegmentsFetcher] is optional and only wired on server-side topology
  /// (reusing `SegmentChangesFetcher.fetch`, which refreshes every registered
  /// segment): on catch-up (§11.3), it runs AFTER the flags fetch completes,
  /// mirroring `javascript-commons`'s `pollingManager.syncAll()`
  /// (`definitionsSyncTask.execute().then(() => segmentsSyncTask.execute())`).
  /// Without it, server-side segment stores would stay stale while push is
  /// up, since `SyncManager.onStreamingUp()` cancels the segments poll
  /// timer for the duration.
  /// [ffCoordinator]/[rbsCoordinator]/[segmentCoordinator] are optional
  /// (spec §10.2): when present, they replace the single unconditional
  /// fetch a fetch-required flag/RBS/segment notification would otherwise
  /// trigger with a retry+backoff+CDN-bypass chase to the notified
  /// `changeNumber`. [segmentCoordinator] is tried before [segmentFetcher]
  /// for `SEGMENT_UPDATE`; [segmentFetcher] remains the fallback (and the
  /// only path on client-side / when no coordinator is wired).
  FeedUpdateRouter({
    required FlagsFetcher flagsFetcher,
    MembershipsFetcher? membershipsFetcher,
    Future<bool> Function(String segmentName)? segmentFetcher,
    Future<bool> Function()? allSegmentsFetcher,
    SegmentUpdateCoordinator? segmentCoordinator,
    OnDemandFetchCoordinator? ffCoordinator,
    OnDemandFetchCoordinator? rbsCoordinator,
    required FlagUpdateStrategy flagStrategy,
    MembershipUpdateStrategy? membershipStrategy,
    required SyncDelayCalculator syncDelayCalculator,
    required Scheduler scheduler,
    required List<String> Function() matchingKeys,
    required NotificationProcessor notificationProcessor,
    required Future<void> Function(StreamingEvent event) apply,
    required SplitLogger logger,
  })  : _segmentFetcher = segmentFetcher,
        _allSegmentsFetcher = allSegmentsFetcher,
        _segmentCoordinator = segmentCoordinator,
        _flagHandler = FlagFeedHandler(
          flagsFetcher: flagsFetcher,
          flagStrategy: flagStrategy,
          allSegmentsFetcher: allSegmentsFetcher,
          ffCoordinator: ffCoordinator,
          rbsCoordinator: rbsCoordinator,
          logger: logger,
        ),
        _membershipDispatcher = MembershipFeedDispatcher(
          membershipsFetcher: membershipsFetcher,
          membershipStrategy: membershipStrategy,
          syncDelayCalculator: syncDelayCalculator,
          scheduler: scheduler,
          matchingKeys: matchingKeys,
          logger: logger,
        ),
        _notificationProcessor = notificationProcessor,
        _apply = apply,
        _log = logger;

  /// Routes one incoming SSE frame: categorize, then either drive the FSM (for
  /// control/occupancy/error) or dispatch data updates to the strategy handlers.
  Future<void> onMessage(RawNotification notification) async {
    if (_log.isVerboseEnabled) {
      _log.verbose('StreamingManager: SSE frame received '
          'event=${notification.event} channel=${notification.channel} '
          'data=${notification.rawData}');
    } else if (_log.isDebugEnabled) {
      _log.debug('StreamingManager: SSE frame '
          'event=${notification.event} '
          'type=${notification.data?['type'] ?? '(none)'}');
    }
    final NotificationResult result;
    try {
      result = _notificationProcessor.process(notification);
    } catch (e) {
      _log.warning('StreamingManager: notification processing failed: $e');
      return;
    }

    if (result.isEmpty) {
      _log.verbose('StreamingManager: frame ignored (no action)');
    }

    final fsmEvent = result.fsmEvent;
    if (fsmEvent != null) {
      await _apply(fsmEvent);
    }
    for (final update in result.feedUpdates) {
      route(update);
    }
  }

  /// Catch-up fetch on (re)connect/recovery (the FSM `Fetch` effect, §11.3):
  /// refresh rules, then (client-side) memberships and/or (server-side, when
  /// [_allSegmentsFetcher] is wired) every tracked segment. Fire-and-forget;
  /// errors are swallowed. On server-side the memberships fetcher is absent,
  /// so [_membershipDispatcher.catchUp] is a no-op there; symmetrically,
  /// client-side has no [_allSegmentsFetcher].
  ///
  /// The segments fetch runs sequentially AFTER flags completes (not
  /// concurrently) — mirroring `javascript-commons`'s
  /// `pollingManager.syncAll()` — because segments newly referenced by rules
  /// fetched during this same catch-up must already be registered before
  /// they can be fetched.
  void catchUp() {
    final allSegmentsFetcher = _allSegmentsFetcher;
    _log.debug('StreamingManager: catch-up fetch '
        '(rules'
        '${_membershipDispatcher.isPresent ? ' + memberships' : ''}'
        '${allSegmentsFetcher != null ? ' + segments' : ''})');
    final flagsDone = _flagHandler.fetchFlags();
    if (allSegmentsFetcher != null) {
      unawaited(
          flagsDone.then((_) => allSegmentsFetcher().catchError((Object e) {
                _log.warning(
                    'StreamingManager: catch-up segments fetch failed: $e');
                return false;
              })));
    } else {
      unawaited(flagsDone);
    }
    _membershipDispatcher.catchUp();
  }

  void route(FeedUpdate update) {
    try {
      if (update.type.startsWith('SPLIT_') ||
          update.type == 'RB_SEGMENT_UPDATE') {
        _flagHandler.route(update);
      } else if (update.type.startsWith('MEMBERSHIPS_')) {
        _membershipDispatcher.route(update);
      } else if (update.type == 'SEGMENT_UPDATE') {
        _routeSegmentUpdate(update);
      }
    } catch (e) {
      _log.warning('StreamingManager: feed update routing failed: $e');
    }
  }

  /// Server-side segment membership update: refresh the named segment via the
  /// injected [_segmentCoordinator] (preferred, spec §10.2 retry/backoff/
  /// CDN-bypass) or [_segmentFetcher] (plain single fetch, used when no
  /// coordinator is wired or the payload carries no int `changeNumber`).
  /// In-place apply is intentionally not attempted — the notification carries
  /// no membership delta, only a change-number bump signalling the SDK to
  /// fetch. Ignored on client-side topology (neither is wired).
  void _routeSegmentUpdate(FeedUpdate update) {
    final name = update.payload['segmentName'];
    if (name is! String || name.isEmpty) {
      _log.warning('StreamingManager: SEGMENT_UPDATE missing segmentName');
      return;
    }
    final coordinator = _segmentCoordinator;
    final changeNumber = update.payload['changeNumber'];
    if (coordinator != null && changeNumber is int) {
      _log.debug('StreamingManager: SEGMENT_UPDATE for "$name" → on-demand '
          'fetch coordinator (cn=$changeNumber)');
      coordinator.notify(name, changeNumber);
      return;
    }
    final fetcher = _segmentFetcher;
    if (fetcher == null) {
      _log.verbose('StreamingManager: SEGMENT_UPDATE ignored '
          '(no segment fetcher — client-side topology)');
      return;
    }
    _log.debug('StreamingManager: SEGMENT_UPDATE for "$name" → fetch');
    unawaited(fetcher(name).catchError((Object e) {
      _log.warning('StreamingManager: segment fetch for "$name" failed: $e');
      return false;
    }));
  }

  /// Cancels every on-demand coordinator's pending retry timer. MUST be
  /// called by [StreamingManager] on `stop()`/destroy so no timer outlives it
  /// (Factory Lifecycle Rules).
  void dispose() {
    _flagHandler.dispose();
    _segmentCoordinator?.dispose();
  }
}
