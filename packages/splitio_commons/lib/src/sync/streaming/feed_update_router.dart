import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';

import '../fetchers/flags_fetcher.dart';
import '../fetchers/memberships_fetcher.dart';
import 'clock.dart';
import 'event_source_client.dart';
import 'flag_update_strategy.dart';
import 'membership_update_strategy.dart';
import 'notification_processor.dart';
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
  final FlagsFetcher _flagsFetcher;
  final MembershipsFetcher _membershipsFetcher;
  final FlagUpdateStrategy _flagStrategy;
  final MembershipUpdateStrategy _membershipStrategy;
  final SyncDelayCalculator _syncDelayCalculator;
  final Scheduler _scheduler;
  final List<String> Function() _matchingKeys;
  final NotificationProcessor _notificationProcessor;
  final Future<void> Function(StreamingEvent event) _apply;
  final SplitLogger _log;

  const FeedUpdateRouter({
    required FlagsFetcher flagsFetcher,
    required MembershipsFetcher membershipsFetcher,
    required FlagUpdateStrategy flagStrategy,
    required MembershipUpdateStrategy membershipStrategy,
    required SyncDelayCalculator syncDelayCalculator,
    required Scheduler scheduler,
    required List<String> Function() matchingKeys,
    required NotificationProcessor notificationProcessor,
    required Future<void> Function(StreamingEvent event) apply,
    required SplitLogger logger,
  })  : _flagsFetcher = flagsFetcher,
        _membershipsFetcher = membershipsFetcher,
        _flagStrategy = flagStrategy,
        _membershipStrategy = membershipStrategy,
        _syncDelayCalculator = syncDelayCalculator,
        _scheduler = scheduler,
        _matchingKeys = matchingKeys,
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
  /// refresh rules and memberships. Fire-and-forget; errors are swallowed.
  void catchUp() {
    _log.debug('StreamingManager: catch-up fetch (rules + memberships)');
    unawaited(_flagsFetcher.fetch().catchError((Object e) {
      _log.warning('StreamingManager: catch-up flags fetch failed: $e');
      return false;
    }));
    unawaited(_membershipsFetcher.fetch().catchError((Object e) {
      _log.warning('StreamingManager: catch-up memberships fetch failed: $e');
      return false;
    }));
  }

  void route(FeedUpdate update) {
    try {
      if (update.type.startsWith('SPLIT_') ||
          update.type == 'RB_SEGMENT_UPDATE') {
        _routeFlagUpdate(update);
      } else if (update.type.startsWith('MEMBERSHIPS_')) {
        _routeMembershipUpdate(update);
      }
    } catch (e) {
      _log.warning('StreamingManager: feed update routing failed: $e');
    }
  }

  void _routeFlagUpdate(FeedUpdate update) {
    // RB_SEGMENT_UPDATE: FlagUpdateStrategy (task 4.4) only applies SPLIT_UPDATE
    // and SPLIT_KILL in place; every other type — including RB_SEGMENT_UPDATE —
    // hits its default branch and returns fetchRequired. In-place RBS apply
    // (decompression + rule-based-segment store mutation) is DEFERRED to a later
    // increment, so a full /splitChanges fetch is the correct safe fallback for
    // now. We short-circuit here rather than round-tripping through the strategy
    // to make the "always fetch" contract explicit at the routing layer.
    if (update.type == 'RB_SEGMENT_UPDATE') {
      _log.debug('StreamingManager: ${update.type} → full flags fetch');
      unawaited(_safeFlagsFetch());
      return;
    }
    final result = _flagStrategy.handle(update);
    _log.debug('StreamingManager: ${update.type} → ${result.outcome.name}');
    if (result.outcome == FlagUpdateOutcome.fetchRequired) {
      unawaited(_safeFlagsFetch());
    }
  }

  Future<void> _safeFlagsFetch() =>
      _flagsFetcher.fetch().catchError((Object e) {
        _log.warning('StreamingManager: flags fetch failed: $e');
        return false;
      });

  void _routeMembershipUpdate(FeedUpdate update) {
    final keys = _matchingKeys();
    for (final key in keys) {
      final result = _membershipStrategy.handle(update, key);
      if (!result.fetchRequired) {
        _log.verbose('StreamingManager: ${update.type} for "$key" → no fetch');
        continue;
      }
      _log.debug('StreamingManager: ${update.type} for "$key" → fetch');
      _scheduleMembershipFetch(update, key);
    }
  }

  /// Schedules the per-key membership fetch, applying seed-based jitter only for
  /// UNBOUNDED/BOUNDED fetch notifications (§12.3); other fetch fallbacks run
  /// immediately.
  void _scheduleMembershipFetch(FeedUpdate update, String key) {
    final payload = update.payload;
    final u = payload['u'];
    final strategy = _strategyFor(u);
    final delayMs = _syncDelayCalculator.delayMs(
      matchingKey: key,
      strategy: strategy,
      i: payload['i'] is int ? payload['i'] as int : null,
      h: payload['h'] is int
          ? payload['h'] as int
          : HashingAlgorithm.murmur3_32,
      s: payload['s'] is int ? payload['s'] as int : null,
    );
    if (delayMs <= 0) {
      unawaited(_safeMembershipsFetch(key));
      return;
    }
    _scheduler.schedule(
      Duration(milliseconds: delayMs),
      () => unawaited(_safeMembershipsFetch(key)),
    );
  }

  MembershipStrategy _strategyFor(Object? u) {
    switch (u) {
      case 0:
        return MembershipStrategy.unbounded;
      case 1:
        return MembershipStrategy.bounded;
      case 2:
        return MembershipStrategy.keyList;
      default:
        return MembershipStrategy.segmentRemoval;
    }
  }

  Future<void> _safeMembershipsFetch(String key) =>
      _membershipsFetcher.fetchForKey(key).catchError((Object e) {
        _log.warning('StreamingManager: memberships fetch failed: $e');
        return false;
      });
}
