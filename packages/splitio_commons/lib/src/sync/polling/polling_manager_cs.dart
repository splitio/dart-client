import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/fetchers/flags_fetcher.dart';
import 'package:splitio_commons/src/sync/fetchers/memberships_fetcher.dart';
import 'package:splitio_commons/src/sync/polling/polling_manager.dart';

/// Client-side polling: one rules timer plus one memberships timer per bound
/// key (spec §8.4, §10). Mirrors JS `pollingManagerCS`.
class PollingManagerCS implements PollingManager {
  final String _bootstrapKey;
  final FlagsFetcher _flagsFetcher;
  final MembershipsFetcher _membershipsFetcher;
  final Duration _featuresRefreshRate;
  final Duration _membershipsRefreshRate;
  final SplitLogger _log;

  Timer? _rulesTimer;
  final Map<String, Timer> _membershipsTimers = {};
  bool _running = false;

  PollingManagerCS({
    required String bootstrapKey,
    required FlagsFetcher flagsFetcher,
    required MembershipsFetcher membershipsFetcher,
    required Duration featuresRefreshRate,
    required Duration membershipsRefreshRate,
    required SplitLogger logger,
  })  : _bootstrapKey = bootstrapKey,
        _flagsFetcher = flagsFetcher,
        _membershipsFetcher = membershipsFetcher,
        _featuresRefreshRate = featuresRefreshRate,
        _membershipsRefreshRate = membershipsRefreshRate,
        _log = logger;

  @override
  bool get isRunning => _running;

  /// Number of live poll timers: the rules timer plus one per bound key
  /// (test/observation hook — used to assert no timer leaks across
  /// streaming up/down cycles).
  int get activePollTimerCount =>
      (_rulesTimer != null ? 1 : 0) + _membershipsTimers.length;

  /// Fetches the rules and the bootstrap key's memberships in parallel.
  @override
  Future<bool> syncAll() async {
    _membershipsFetcher.bindKey(_bootstrapKey);
    _log.debug('Starting initial sync for key: $_bootstrapKey');

    final results = await Future.wait([
      _flagsFetcher.fetch(),
      _membershipsFetcher.fetchForKey(_bootstrapKey),
    ]);

    final rulesOk = results[0];
    final membershipsOk = results[1];

    if (!rulesOk || !membershipsOk) {
      if (!rulesOk) _log.error('Initial targeting rules fetch failed');
      if (!membershipsOk) _log.error('Initial memberships fetch failed');
      return false;
    }

    _log.info('Initial sync complete');
    return true;
  }

  /// Binds [key], arms its memberships timer if running, fetches once.
  Future<bool> syncMembershipsFor(String key) {
    _membershipsFetcher.bindKey(key);
    if (_running) _startMembershipsTimerFor(key);
    return _membershipsFetcher.fetchForKey(key);
  }

  @override
  void start() {
    // True idempotency (§11.3): once polling is already running, repeated
    // calls (e.g. one per retryable streaming failure while streaming never
    // comes up) MUST NOT touch the existing timers. Cancelling and recreating
    // the periodic rules timer on every call resets its elapsed time toward
    // the next fire, so a failure cadence faster than the poll period would
    // starve the rules timer forever and it would never fire.
    if (_running) return;
    _log.debug(
        'Starting polling (rules: ${_featuresRefreshRate.inSeconds}s, memberships: ${_membershipsRefreshRate.inSeconds}s)');
    _running = true;
    _rulesTimer =
        Timer.periodic(_featuresRefreshRate, (_) => _flagsFetcher.fetch());
    for (final key in _membershipsFetcher.boundKeys) {
      _startMembershipsTimerFor(key);
    }
  }

  @override
  void stop() {
    _rulesTimer?.cancel();
    _rulesTimer = null;
    for (final t in _membershipsTimers.values) {
      t.cancel();
    }
    _membershipsTimers.clear();
    _running = false;
  }

  void _startMembershipsTimerFor(String key) {
    if (_membershipsTimers.containsKey(key)) return;
    _membershipsTimers[key] = Timer.periodic(
      _membershipsRefreshRate,
      (_) => _membershipsFetcher.fetchForKey(key),
    );
  }
}
