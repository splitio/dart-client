import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';

import '../fetchers/memberships_fetcher.dart';
import 'clock.dart';
import 'membership_update_strategy.dart';
import 'notification_processor.dart';
import 'sync_delay_calculator.dart';

/// Dispatches `MEMBERSHIPS_*` [FeedUpdate]s to the per-key [MembershipUpdateStrategy]
/// and runs the resulting per-key fetches, applying seed-based jitter (§12.3)
/// to unbounded/bounded fetch notifications via the injected
/// [SyncDelayCalculator] + [Scheduler]. Also owns the client-side half of the
/// catch-up fetch (spec §11.3): refreshing memberships on (re)connect/recovery.
///
/// Extracted from [FeedUpdateRouter] (Tidy First) — this cluster of methods
/// touches a disjoint subset of fields (membership strategy, matching keys,
/// jitter calculator, memberships fetcher) from flag/segment routing, so it
/// is its own class rather than a size-driven split of unrelated concerns.
///
/// [membershipsFetcher] and [membershipStrategy] are optional: when absent
/// (server-side topology, spec §17.2 Axis 3), `MEMBERSHIPS_MS/LS_UPDATE`
/// frames are ignored and [catchUp] is a no-op — mirroring
/// `javascript-commons` `pushManager.ts`, which only subscribes the membership
/// handlers when a `userKey` is bound.
class MembershipFeedDispatcher {
  final MembershipsFetcher? _membershipsFetcher;
  final MembershipUpdateStrategy? _membershipStrategy;
  final SyncDelayCalculator _syncDelayCalculator;
  final Scheduler _scheduler;
  final List<String> Function() _matchingKeys;
  final SplitLogger _log;

  const MembershipFeedDispatcher({
    MembershipsFetcher? membershipsFetcher,
    MembershipUpdateStrategy? membershipStrategy,
    required SyncDelayCalculator syncDelayCalculator,
    required Scheduler scheduler,
    required List<String> Function() matchingKeys,
    required SplitLogger logger,
  })  : _membershipsFetcher = membershipsFetcher,
        _membershipStrategy = membershipStrategy,
        _syncDelayCalculator = syncDelayCalculator,
        _scheduler = scheduler,
        _matchingKeys = matchingKeys,
        _log = logger;

  /// Whether a memberships fetcher is wired (client-side topology).
  bool get isPresent => _membershipsFetcher != null;

  /// Catch-up fetch on (re)connect/recovery (the FSM `Fetch` effect, §11.3):
  /// refreshes memberships for every bound matching key. Fire-and-forget;
  /// errors are swallowed. No-op when no memberships fetcher is wired
  /// (server-side topology).
  void catchUp() {
    final fetcher = _membershipsFetcher;
    if (fetcher == null) return;
    unawaited(fetcher.fetch().catchError((Object e) {
      _log.warning('StreamingManager: catch-up memberships fetch failed: $e');
      return false;
    }));
  }

  /// Routes one `MEMBERSHIPS_*` [FeedUpdate] to every currently bound
  /// matching key, scheduling a fetch (with jitter where applicable) for each
  /// key the [MembershipUpdateStrategy] says requires one.
  void route(FeedUpdate update) {
    final strategy = _membershipStrategy;
    if (strategy == null) {
      // Server-side topology: no per-key memberships. Ignore MEMBERSHIPS_*
      // frames, matching `javascript-commons` pushManager.ts (subscribes the
      // membership handlers only when `userKey` is bound).
      _log.verbose('StreamingManager: ${update.type} ignored (no membership '
          'strategy — server-side topology)');
      return;
    }
    final keys = _matchingKeys();
    for (final key in keys) {
      final result = strategy.handle(update, key);
      if (!result.fetchRequired) {
        // In-place apply (spec §12.2): report the change on the shared
        // fetcher instance so `whenUpdated()` fires with an empty payload
        // (spec §4.6/§8.2), mirroring how a real fetch's change is reported.
        if (result.changed) _membershipsFetcher?.notifyUpdate(key);
        _log.verbose('StreamingManager: ${update.type} for "$key" → no fetch');
        continue;
      }
      _log.debug('StreamingManager: ${update.type} for "$key" → fetch');
      _scheduleFetch(update, key);
    }
  }

  /// Schedules the per-key membership fetch, applying seed-based jitter only
  /// for UNBOUNDED/BOUNDED fetch notifications (§12.3); other fetch
  /// fallbacks run immediately.
  void _scheduleFetch(FeedUpdate update, String key) {
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
      unawaited(_safeFetch(key));
      return;
    }
    _scheduler.schedule(
      Duration(milliseconds: delayMs),
      () => unawaited(_safeFetch(key)),
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

  Future<void> _safeFetch(String key) {
    final fetcher = _membershipsFetcher;
    if (fetcher == null) return Future.value();
    return fetcher.fetchForKey(key).catchError((Object e) {
      _log.warning('StreamingManager: memberships fetch failed: $e');
      return false;
    });
  }
}
