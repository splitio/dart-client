import 'package:splitio_commons/src/auth/auth.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/streaming/reconnect_scheduler.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Direct unit tests for [ReconnectScheduler] (spec §11.3, §19.5): the
/// reconnect-backoff timer and the proactive token-refresh timer. Backoff
/// growth is also exercised indirectly through [StreamingManager] in
/// `streaming_manager_test.dart`'s "backoff grows across reconnect attempts"
/// test, but this file isolates the scheduler itself so its dedup, cap, and
/// reset semantics are verified without needing a full FSM/SSE stack.
void main() {
  late FakeScheduler scheduler;
  late FakeClock clock;
  late int reconnectCalls;
  late int refreshCalls;
  late ReconnectScheduler rs;

  setUp(() {
    scheduler = FakeScheduler();
    clock = FakeClock();
    reconnectCalls = 0;
    refreshCalls = 0;
    rs = ReconnectScheduler(
      scheduler: scheduler,
      clock: clock,
      logger: SplitLogger(level: LogLevel.none),
      onReconnect: () => reconnectCalls++,
      onRefresh: () => refreshCalls++,
    );
  });

  group('scheduleReconnect backoff', () {
    test('first call schedules at the base delay (1000ms)', () {
      rs.scheduleReconnect();
      expect(scheduler.pendingCount, 1);
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 1000));
      expect(rs.backoffAttempt, 1);
    });

    test('backoff doubles on each consecutive call: 1s, 2s, 4s, 8s', () {
      rs.scheduleReconnect();
      scheduler.flush();
      expect(scheduler.pendingDelays, isEmpty);

      rs.scheduleReconnect();
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 2000));
      scheduler.flush();

      rs.scheduleReconnect();
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 4000));
      scheduler.flush();

      rs.scheduleReconnect();
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 8000));
    });

    test('backoff is capped at 30 minutes (1_800_000ms)', () {
      // Drive the attempt counter well past the point where
      // base * 2^attempt would overflow the cap.
      for (var i = 0; i < 30; i++) {
        rs.scheduleReconnect();
        scheduler.flush();
      }
      rs.scheduleReconnect();
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 1800000),
          reason: 'backoff MUST clamp to the 30-minute cap rather than grow '
              'unbounded (and MUST NOT go negative on overflow)');
    });

    test(
        'a second call while one reconnect is already pending is a no-op '
        '(dedup, §11.3)', () {
      rs.scheduleReconnect();
      expect(scheduler.pendingCount, 1);
      final firstDelay = scheduler.pendingDelays.single;

      // A second failure arrives before the first reconnect fires.
      rs.scheduleReconnect();

      expect(scheduler.pendingCount, 1,
          reason: 'at most one reconnect may be pending at a time');
      expect(scheduler.pendingDelays.single, firstDelay,
          reason: 'the already-armed timer MUST NOT be replaced/rescheduled');
      expect(rs.backoffAttempt, 1,
          reason:
              'the backoff attempt counter MUST NOT advance on a deduped call');
    });

    test('firing the scheduled callback invokes onReconnect exactly once', () {
      rs.scheduleReconnect();
      scheduler.flush();
      expect(reconnectCalls, 1);
      expect(refreshCalls, 0);
    });

    test('resetBackoff() restarts the attempt counter from zero', () {
      rs.scheduleReconnect();
      scheduler.flush();
      rs.scheduleReconnect();
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 2000));
      scheduler.flush();

      rs.resetBackoff();

      rs.scheduleReconnect();
      expect(scheduler.pendingDelays.single, const Duration(milliseconds: 1000),
          reason: 'after resetBackoff(), the next reconnect MUST start again '
              'from the base delay');
      expect(rs.backoffAttempt, 1);
    });

    test('cancelReconnect() cancels a pending reconnect and allows a fresh one',
        () {
      rs.scheduleReconnect();
      expect(scheduler.pendingCount, 1);

      rs.cancelReconnect();
      expect(scheduler.pendingCount, 0);

      // Dedup no longer applies: a new reconnect can be armed immediately.
      rs.scheduleReconnect();
      expect(scheduler.pendingCount, 1);
    });

    test('cancelReconnect() is idempotent when nothing is pending', () {
      expect(() => rs.cancelReconnect(), returnsNormally);
      rs.cancelReconnect();
      rs.cancelReconnect();
      expect(scheduler.pendingCount, 0);
    });

    test(
        'scheduleReconnect() cancels any pending proactive token refresh '
        '(§11.3)', () {
      rs.scheduleTokenRefresh(
        connectionUp: true,
        jwt: JwtCredential(
          token: 't',
          channels: const [],
          pushEnabled: true,
          // Far enough in the future that the lead-time delay isn't clamped.
          expiresAt: clock.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          connDelaySeconds: 0,
        ),
      );
      expect(scheduler.pendingCount, 1, reason: 'refresh timer armed');

      rs.scheduleReconnect();

      // The refresh timer is replaced by the reconnect timer: still exactly
      // one pending callback, and it is the reconnect (not the refresh).
      expect(scheduler.pendingCount, 1);
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 1000));
      scheduler.flush();
      expect(reconnectCalls, 1);
      expect(refreshCalls, 0,
          reason: 'the stale refresh MUST NOT fire against a dead connection');
    });
  });

  group('scheduleTokenRefresh', () {
    JwtCredential jwtExpiringIn(Duration ttl) => JwtCredential(
          token: 't',
          channels: const [],
          pushEnabled: true,
          expiresAt: clock.now().add(ttl).millisecondsSinceEpoch ~/ 1000,
          connDelaySeconds: 0,
        );

    test('schedules at expiresAt - 10min lead time when that is in the future',
        () {
      // TTL of 30 minutes: lead-adjusted delay = 30min - 10min = 20min.
      rs.scheduleTokenRefresh(
          connectionUp: true, jwt: jwtExpiringIn(const Duration(minutes: 30)));

      expect(scheduler.pendingCount, 1);
      expect(scheduler.pendingDelays.single, const Duration(minutes: 20));
    });

    test('clamps to the 1s minimum delay for a short-TTL token', () {
      // TTL of 60s: expiresAt - 10min lead time is already in the past.
      rs.scheduleTokenRefresh(
          connectionUp: true, jwt: jwtExpiringIn(const Duration(seconds: 60)));

      expect(scheduler.pendingCount, 1);
      expect(scheduler.pendingDelays.single, const Duration(seconds: 1));
    });

    test('does nothing when connectionUp is false', () {
      rs.scheduleTokenRefresh(
          connectionUp: false, jwt: jwtExpiringIn(const Duration(minutes: 30)));

      expect(scheduler.pendingCount, 0,
          reason: 'a stale schedule MUST NOT arm a timer once the connection '
              'is no longer up; the next successful open rearms it');
    });

    test('does nothing when jwt is null', () {
      rs.scheduleTokenRefresh(connectionUp: true, jwt: null);
      expect(scheduler.pendingCount, 0);
    });

    test(
        'replaces any previously-scheduled refresh (only one pending at a '
        'time)', () {
      rs.scheduleTokenRefresh(
          connectionUp: true, jwt: jwtExpiringIn(const Duration(minutes: 30)));
      expect(scheduler.pendingCount, 1);

      rs.scheduleTokenRefresh(
          connectionUp: true, jwt: jwtExpiringIn(const Duration(minutes: 45)));

      expect(scheduler.pendingCount, 1,
          reason: 'at most one refresh may ever be pending');
      expect(scheduler.pendingDelays.single, const Duration(minutes: 35));
    });

    test('firing the scheduled callback invokes onRefresh exactly once', () {
      rs.scheduleTokenRefresh(
          connectionUp: true, jwt: jwtExpiringIn(const Duration(minutes: 30)));
      scheduler.flush();

      expect(refreshCalls, 1);
      expect(reconnectCalls, 0);
    });

    test('cancelTokenRefresh() cancels a pending refresh', () {
      rs.scheduleTokenRefresh(
          connectionUp: true, jwt: jwtExpiringIn(const Duration(minutes: 30)));
      expect(scheduler.pendingCount, 1);

      rs.cancelTokenRefresh();

      expect(scheduler.pendingCount, 0);
    });

    test('cancelTokenRefresh() is idempotent when nothing is pending', () {
      expect(() => rs.cancelTokenRefresh(), returnsNormally);
      rs.cancelTokenRefresh();
      expect(scheduler.pendingCount, 0);
    });
  });
}
