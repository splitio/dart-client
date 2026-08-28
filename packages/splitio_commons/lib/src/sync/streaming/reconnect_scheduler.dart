import 'package:splitio_commons/src/auth/auth.dart';
import 'package:splitio_commons/src/logger/logger.dart';

import 'clock.dart';

/// Owns the reconnect-backoff timer and the proactive token-refresh timer for
/// the streaming connection (spec §11.3, §19.5).
///
/// Both timers are single-shot and deduped: at most one reconnect and one
/// refresh may ever be pending. When they fire they invoke the injected
/// [onReconnect]/[onRefresh] callbacks, which drive the FSM back in the
/// [StreamingManager]. All timer scheduling goes through the injected
/// [Scheduler]/[Clock] so behaviour is deterministic in tests.
class ReconnectScheduler {
  /// Backoff bounds (spec §19.5): `min(base · 2^attempt, cap)`.
  static const Duration _backoffBase = Duration(milliseconds: 1000);
  static const Duration _backoffCap = Duration(milliseconds: 1800000);

  /// Proactive token refresh (spec §11.3): the streaming token is refreshed
  /// [_refreshLeadTime] before its `expiresAt`. When `expiresAt − leadTime` is
  /// already in the past (short-TTL token), the delay is clamped to
  /// [_minRefreshDelay] so the refresh still fires before expiry.
  static const Duration _refreshLeadTime = Duration(minutes: 10);
  static const Duration _minRefreshDelay = Duration(seconds: 1);

  final Scheduler _scheduler;
  final Clock _clock;
  final SplitLogger _log;
  final void Function() _onReconnect;
  final void Function() _onRefresh;

  Object? _reconnectHandle;
  int _backoffAttempt = 0;
  Object? _refreshHandle;

  /// The current exponential-backoff attempt counter (log/observation hook).
  int get backoffAttempt => _backoffAttempt;

  ReconnectScheduler({
    required Scheduler scheduler,
    required Clock clock,
    required SplitLogger logger,
    required void Function() onReconnect,
    required void Function() onRefresh,
  })  : _scheduler = scheduler,
        _clock = clock,
        _log = logger,
        _onReconnect = onReconnect,
        _onRefresh = onRefresh;

  /// Schedules a deduped, backed-off reconnect. Only one reconnect may be
  /// pending at a time (§11.3): a second call while one is armed is a no-op, so
  /// failures never stack multiple pending timers.
  void scheduleReconnect() {
    if (_reconnectHandle != null) {
      _log.verbose('StreamingManager: reconnect already scheduled — skipped');
      return;
    }
    // The current socket is dead; cancel any pending proactive refresh so it
    // does not fire against a connection that is already reconnecting (§11.3).
    // A fresh refresh is rearmed on the next successful open.
    cancelTokenRefresh();
    final delay = _nextBackoff();
    _log.debug(
        'StreamingManager: scheduling reconnect in ${delay.inMilliseconds}ms '
        '(attempt $_backoffAttempt)');
    _reconnectHandle = _scheduler.schedule(delay, () {
      _reconnectHandle = null;
      _onReconnect();
    });
  }

  Duration _nextBackoff() {
    final attempt = _backoffAttempt;
    _backoffAttempt++;
    final ms = _backoffBase.inMilliseconds * (1 << attempt);
    final capped = ms > _backoffCap.inMilliseconds || ms < 0
        ? _backoffCap.inMilliseconds
        : ms;
    return Duration(milliseconds: capped);
  }

  /// Resets the exponential-backoff attempt counter (the FSM `ResetBackoff`
  /// effect), so the next reconnect starts from the base delay.
  void resetBackoff() {
    _backoffAttempt = 0;
  }

  void cancelReconnect() {
    final handle = _reconnectHandle;
    if (handle != null) {
      _scheduler.cancel(handle);
      _reconnectHandle = null;
    }
  }

  /// (Re)schedules the single proactive token-refresh timer to fire
  /// [_refreshLeadTime] before [jwt]'s `expiresAt`. Any existing timer is
  /// cancelled first, so at most one is ever pending and a reconnect always
  /// rearms from the fresh credential's expiry. When `expiresAt − leadTime` is
  /// already in the past (short-TTL token), the delay is clamped to
  /// [_minRefreshDelay] so the refresh still fires before expiry.
  ///
  /// [connectionUp] gates arming the timer: effect execution can interleave with
  /// a reentrant SocketError (e.g. the stream ends immediately after opening),
  /// so a stale schedule must not rearm a timer once the connection is no longer
  /// up. The next successful open rearms it.
  void scheduleTokenRefresh({
    required bool connectionUp,
    required JwtCredential? jwt,
  }) {
    cancelTokenRefresh();
    if (!connectionUp) {
      _log.verbose('StreamingManager: skip token refresh schedule '
          '(connection not up)');
      return;
    }
    if (jwt == null) {
      _log.verbose('StreamingManager: no credential to schedule token refresh');
      return;
    }
    // expiresAt is epoch SECONDS; the clock is in milliseconds.
    final expiresAtMs = jwt.expiresAt * 1000;
    final leadMs = _refreshLeadTime.inMilliseconds;
    final nowMs = _clock.now().millisecondsSinceEpoch;
    final rawDelayMs = expiresAtMs - leadMs - nowMs;
    final delay = rawDelayMs > _minRefreshDelay.inMilliseconds
        ? Duration(milliseconds: rawDelayMs)
        : _minRefreshDelay;
    _log.debug(
        'StreamingManager: scheduling token refresh in ${delay.inMilliseconds}ms');
    _refreshHandle = _scheduler.schedule(delay, () {
      _refreshHandle = null;
      _onRefresh();
    });
  }

  void cancelTokenRefresh() {
    final handle = _refreshHandle;
    if (handle != null) {
      _scheduler.cancel(handle);
      _refreshHandle = null;
    }
  }
}
