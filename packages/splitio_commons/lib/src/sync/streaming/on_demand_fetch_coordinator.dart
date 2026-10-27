import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';

import 'clock.dart';

/// Chases a single streaming-notified `changeNumber` to convergence with
/// backoff and a CDN-bypass fallback (spec §10.2 / §19.5).
///
/// A fetch triggered by a `SPLIT_UPDATE`/`SPLIT_KILL`/`RB_SEGMENT_UPDATE`/
/// `SEGMENT_UPDATE` notification can return a stale CDN response (0 changes)
/// even though the notified change genuinely exists — a propagation-lag
/// artifact. Without this, the SDK would stay on the stale definition
/// forever, since polling is off while push is up.
///
/// On [notify], if not already caught up to (or past) the notified
/// `changeNumber`, it fetches with `Cache-Control: no-cache` immediately,
/// then retries with exponential backoff (base 10s, cap 60s) for up to 10
/// attempts total. If the cursor (read via the injected [cursor] callback,
/// checked only AFTER each fetch completes) is still behind, it makes
/// exactly one more fetch with `till=<changeNumber>` to force a CDN cache
/// bypass, then gives up until the next [notify] call or an unrelated
/// poll/catch-up converges it instead.
///
/// A newer [notify] call arriving mid-chase restarts the whole sequence
/// (fresh attempts/bypass state) targeting the new, higher `changeNumber`.
///
/// One instance tracks exactly one cursor (e.g. the `ff` cursor, the `rbs`
/// cursor, or a single server-side segment's own cursor) — callers needing
/// several independent cursors construct one instance per cursor (see
/// [SegmentUpdateCoordinator] for the per-segment-name case).
class OnDemandFetchCoordinator {
  static const _backoffBase = Duration(milliseconds: 10000);
  static const _backoffCap = Duration(milliseconds: 60000);
  static const _maxAttempts = 10;

  final int Function() _cursor;
  final Future<bool> Function({bool noCache, int? till}) _fetch;
  final Scheduler _scheduler;
  final SplitLogger _log;
  final String _name;

  int _maxChangeNumber = -1;
  int _attempts = 0;
  bool _cdnBypassDone = false;
  bool _isHandling = false;
  bool _disposed = false;
  Object? _timerHandle;

  OnDemandFetchCoordinator({
    required int Function() cursor,
    required Future<bool> Function({bool noCache, int? till}) fetch,
    required Scheduler scheduler,
    required SplitLogger logger,
    String name = 'OnDemandFetchCoordinator',
  })  : _cursor = cursor,
        _fetch = fetch,
        _scheduler = scheduler,
        _log = logger,
        _name = name;

  /// Notifies the coordinator of a streaming-notified [changeNumber].
  /// Ignored if it is not newer than both the current cursor and any
  /// changeNumber already being chased. Otherwise (re)starts the chase.
  void notify(int changeNumber) {
    if (_disposed) return;
    if (changeNumber <= _cursor() || changeNumber <= _maxChangeNumber) {
      return;
    }
    _maxChangeNumber = changeNumber;
    _attempts = 0;
    _cdnBypassDone = false;
    final hadPendingTimer = _timerHandle != null;
    _cancelPending();
    // A timer was pending (no fetch currently in flight) or nothing was
    // running at all → kick off a fresh attempt now. Otherwise a fetch is
    // already in flight; its completion handler will pick up the reset
    // state above and continue chasing the new target.
    if (!_isHandling || hadPendingTimer) {
      _isHandling = true;
      unawaited(_attempt());
    }
  }

  /// Cancels any pending retry timer. MUST be called by the owner on
  /// stop/destroy so no timer outlives it. A fetch already in flight is
  /// left to finish but schedules nothing further.
  void dispose() {
    _disposed = true;
    _cancelPending();
  }

  void _cancelPending() {
    final handle = _timerHandle;
    if (handle != null) {
      _scheduler.cancel(handle);
      _timerHandle = null;
    }
  }

  Future<void> _attempt() async {
    final target = _maxChangeNumber;
    final bypass = !_cdnBypassDone && _attempts >= _maxAttempts;
    try {
      await _fetch(noCache: true, till: bypass ? target : null);
    } catch (e) {
      _log.warning('$_name: on-demand fetch failed: $e');
    }
    if (_disposed) return;
    if (_maxChangeNumber != target) {
      // A newer notification reset the chase while this fetch was in
      // flight; notify() already reset attempts/bypass — just continue
      // chasing the new target from scratch.
      unawaited(_attempt());
      return;
    }
    if (bypass) _cdnBypassDone = true;
    if (_cursor() >= target) {
      _isHandling = false;
      return;
    }
    if (bypass) {
      _log.debug('$_name: CDN-bypass fetch still behind cn=$target — '
          'giving up until the next notification or poll');
      _isHandling = false;
      return;
    }
    if (_attempts >= _maxAttempts) {
      unawaited(_attempt()); // immediately make the one bypass attempt
      return;
    }
    final delayMs = (_backoffBase.inMilliseconds * (1 << _attempts))
        .clamp(0, _backoffCap.inMilliseconds);
    _attempts++;
    _timerHandle = _scheduler.schedule(Duration(milliseconds: delayMs), () {
      _timerHandle = null;
      unawaited(_attempt());
    });
  }
}
