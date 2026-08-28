import 'package:splitio_commons/src/sync/streaming/streaming_effect.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_event.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_policy.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_state.dart';
import 'package:test/test.dart';

/// A `Started`, fully-connected, push-up state — the common baseline.
StreamingState connected({
  int failures = 0,
  bool controlPaused = false,
  bool occupancyZero = false,
  int lastControl = 0,
}) =>
    StreamingState(
      connState: ConnState.started,
      connectionDown: false,
      consecutiveFailures: failures,
      controlPaused: controlPaused,
      occupancyZero: occupancyZero,
      lastControlTimestamp: lastControl,
    );

void main() {
  group('initial state', () {
    test('defaults: stopped, connectionDown, push down', () {
      const s = StreamingState();
      expect(s.connState, ConnState.stopped);
      expect(s.connectionDown, isTrue);
      expect(s.pushUp, isFalse);
      expect(s.consecutiveFailures, 0);
      expect(s.reconnecting, isFalse);
    });

    test('pushUp is derived from the 3-axis gate', () {
      expect(connected().pushUp, isTrue);
      expect(connected(controlPaused: true).pushUp, isFalse);
      expect(connected(occupancyZero: true).pushUp, isFalse);
      expect(connected().copyWith(connectionDown: true).pushUp, isFalse);
    });
  });

  group('Start', () {
    test('Stopped -> Started emits EmitConnectStarted + OpenSocket', () {
      final r = StreamingPolicy.reduce(const StreamingState(), const Start());
      expect(r.state.connState, ConnState.started);
      expect(r.effects, const [EmitConnectStarted(), OpenSocket()]);
      // Not connected yet: no push edge until SocketOpened.
      expect(r.state.pushUp, isFalse);
    });

    test('Start when already Started is a no-op', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const Start());
      expect(r.state, s);
      expect(r.effects, isEmpty);
    });

    test('Start when Paused is a no-op', () {
      final s = connected().copyWith(connState: ConnState.paused);
      final r = StreamingPolicy.reduce(s, const Start());
      expect(r.effects, isEmpty);
    });
  });

  group('SocketOpened', () {
    test('resets failures/occupancy, ResetBackoff + push up + Fetch', () {
      final s = StreamingState(
        connState: ConnState.started,
        connectionDown: true,
        consecutiveFailures: 3,
        occupancyZero: true,
      );
      final r = StreamingPolicy.reduce(s, const SocketOpened());
      expect(r.state.connectionDown, isFalse);
      expect(r.state.consecutiveFailures, 0);
      // SocketOpened resets occupancy too, so pushUp comes up.
      expect(r.state.occupancyZero, isFalse);
      expect(r.state.pushUp, isTrue);
      expect(r.effects, contains(const ResetBackoff()));
      expect(r.effects, contains(const EmitConnected()));
      expect(r.effects, contains(const NotifyPushEnabled()));
      // Connection-driven up-edge -> sync-mode change to streaming.
      expect(
        r.effects.whereType<EmitSyncModeChanged>().toList(),
        const [
          EmitSyncModeChanged(
            to: SyncMode.streaming,
            reason: SyncModeChangeReason.streamingConnected,
          ),
        ],
      );
    });

    test('from a clean reconnect: connected edge + push up + Fetch', () {
      final s = StreamingState(
        connState: ConnState.started,
        connectionDown: true,
        reconnecting: true,
        consecutiveFailures: 2,
      );
      final r = StreamingPolicy.reduce(s, const SocketOpened());
      expect(r.state.pushUp, isTrue);
      expect(r.state.reconnecting, isFalse);
      expect(
        r.effects,
        containsAllInOrder(const [
          ResetBackoff(),
          EmitConnected(),
          NotifyPushEnabled(),
          EmitSyncModeChanged(
            to: SyncMode.streaming,
            reason: SyncModeChangeReason.streamingConnected,
          ),
          Fetch(),
        ]),
      );
    });

    test('re-entry on already-connected state does not re-emit edges', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const SocketOpened());
      // No connection or push edge -> only ResetBackoff + a (deduped) refresh
      // reschedule from the just-confirmed credential.
      expect(r.effects, const [ResetBackoff(), ScheduleTokenRefresh()]);
    });

    test('SocketOpened when not Started is a no-op', () {
      final r =
          StreamingPolicy.reduce(const StreamingState(), const SocketOpened());
      expect(r.effects, isEmpty);
    });
  });

  group('SocketError', () {
    test('first retryable failure does NOT set connectionDown', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const SocketError(retryable: true));
      expect(r.state.consecutiveFailures, 1);
      expect(r.state.connectionDown, isFalse);
      expect(r.state.reconnecting, isTrue);
      expect(r.effects, const [ScheduleReconnect()]);
    });

    test('second retryable failure sets connectionDown + poll fallback', () {
      final s = connected(failures: 1);
      final r = StreamingPolicy.reduce(s, const SocketError(retryable: true));
      expect(r.state.consecutiveFailures, 2);
      expect(r.state.connectionDown, isTrue);
      expect(r.state.pushUp, isFalse);
      expect(
        r.effects,
        containsAllInOrder(const [
          ScheduleReconnect(),
          EmitDisconnected(),
          NotifyPushDisabled(),
          EmitSyncModeChanged(
            to: SyncMode.polling,
            reason: SyncModeChangeReason.streamingDisconnected,
          ),
        ]),
      );
      // Exactly one connection-driven sync-mode change on the down-edge.
      expect(
        r.effects.whereType<EmitSyncModeChanged>().toList(),
        const [
          EmitSyncModeChanged(
            to: SyncMode.polling,
            reason: SyncModeChangeReason.streamingDisconnected,
          ),
        ],
      );
    });

    test('non-retryable error stops streaming', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const SocketError(retryable: false));
      expect(r.state.connState, ConnState.stopped);
      expect(r.effects, contains(const CloseCurrentSocket()));
    });

    test('SocketError when not Started is a no-op', () {
      final r = StreamingPolicy.reduce(
          const StreamingState(), const SocketError(retryable: true));
      expect(r.effects, isEmpty);
    });
  });

  group('ReconnectTimerFired', () {
    test('while reconnecting re-opens socket', () {
      final s = connected(failures: 2)
          .copyWith(connectionDown: true, reconnecting: true);
      final r = StreamingPolicy.reduce(s, const ReconnectTimerFired());
      expect(r.state.reconnecting, isFalse);
      expect(r.effects, const [EmitConnectStarted(), OpenSocket()]);
    });

    test('when not reconnecting is a no-op', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const ReconnectTimerFired());
      expect(r.effects, isEmpty);
    });
  });

  group('ErrorFrame', () {
    test('token error invalidates token + reconnects', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const ErrorFrame(isTokenError: true));
      expect(r.state.reconnecting, isTrue);
      expect(r.state.connState, ConnState.started);
      expect(r.effects, const [InvalidateToken(), ScheduleReconnect()]);
    });

    test('non-token error stops streaming', () {
      final s = connected();
      final r =
          StreamingPolicy.reduce(s, const ErrorFrame(isTokenError: false));
      expect(r.state.connState, ConnState.stopped);
      expect(r.effects, contains(const CloseCurrentSocket()));
    });

    test('ErrorFrame when not Started is a no-op', () {
      final r = StreamingPolicy.reduce(
          const StreamingState(), const ErrorFrame(isTokenError: true));
      expect(r.effects, isEmpty);
    });
  });

  group('RefreshTokenTimerFired', () {
    test('invalidates token + reconnects (like ControlReset)', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const RefreshTokenTimerFired());
      expect(r.state.reconnecting, isTrue);
      expect(r.state.connState, ConnState.started);
      expect(r.effects, const [InvalidateToken(), ScheduleReconnect()]);
    });

    test('keeps connection up (no premature poll fallback)', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const RefreshTokenTimerFired());
      // Refresh reconnects transparently — push stays up until the socket
      // actually drops, so no NotifyPushDisabled/EmitDisconnected edge fires.
      expect(r.state.pushUp, isTrue);
      expect(r.effects, isNot(contains(const NotifyPushDisabled())));
      expect(r.effects, isNot(contains(const EmitDisconnected())));
    });

    test('when not Started is a no-op', () {
      final r = StreamingPolicy.reduce(
          const StreamingState(), const RefreshTokenTimerFired());
      expect(r.effects, isEmpty);
    });
  });

  group('token-refresh scheduling edges', () {
    test('SocketOpened schedules the proactive token refresh', () {
      final s = StreamingState(
        connState: ConnState.started,
        connectionDown: true,
      );
      final r = StreamingPolicy.reduce(s, const SocketOpened());
      expect(r.effects, contains(const ScheduleTokenRefresh()));
    });

    test('connection down-edge cancels the token refresh', () {
      // Two consecutive retryable failures drop the connection axis.
      final s = connected(failures: 1);
      final r = StreamingPolicy.reduce(s, const SocketError(retryable: true));
      expect(r.state.connectionDown, isTrue);
      expect(r.effects, contains(const CancelTokenRefresh()));
    });

    test('Stop closes the socket (runtime cancels refresh on close)', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const Stop());
      // The down-edge cancels the refresh; CloseCurrentSocket also cancels
      // defensively in the runtime.
      expect(r.effects, contains(const CancelTokenRefresh()));
      expect(r.effects, contains(const CloseCurrentSocket()));
    });
  });

  group('Pause / Resume', () {
    test('Pause closes socket, marks connection down, push down', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const Pause());
      expect(r.state.connState, ConnState.paused);
      expect(r.state.connectionDown, isTrue);
      expect(
        r.effects,
        containsAllInOrder(const [
          CloseCurrentSocket(),
          EmitDisconnected(),
          NotifyPushDisabled(),
        ]),
      );
      // User-driven, not connection-driven -> no EmitSyncModeChanged.
      expect(r.effects.whereType<EmitSyncModeChanged>(), isEmpty);
    });

    test('Resume from Paused re-opens socket', () {
      final s = connected()
          .copyWith(connState: ConnState.paused, connectionDown: true);
      final r = StreamingPolicy.reduce(s, const Resume());
      expect(r.state.connState, ConnState.started);
      expect(r.effects, const [EmitConnectStarted(), OpenSocket()]);
      // Resume opens the socket but push does not come up until SocketOpened,
      // so there is no sync-mode change here.
      expect(r.effects.whereType<EmitSyncModeChanged>(), isEmpty);
    });

    test('Resume when Started is a no-op', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const Resume());
      expect(r.effects, isEmpty);
    });

    test('Pause when Stopped is a no-op', () {
      final r = StreamingPolicy.reduce(const StreamingState(), const Pause());
      expect(r.effects, isEmpty);
    });
  });

  group('Stop / TokenPushDisabled', () {
    test('Stop from Started -> Stopped, closes socket, no reopen', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const Stop());
      expect(r.state.connState, ConnState.stopped);
      expect(r.effects, isNot(contains(const OpenSocket())));
      expect(r.effects, contains(const CloseCurrentSocket()));
      // Stop drops the connection and push, but is user-driven -> no
      // EmitSyncModeChanged.
      expect(r.effects, contains(const NotifyPushDisabled()));
      expect(r.effects.whereType<EmitSyncModeChanged>(), isEmpty);
    });

    test('Stop from Paused -> Stopped', () {
      final s = connected()
          .copyWith(connState: ConnState.paused, connectionDown: true);
      final r = StreamingPolicy.reduce(s, const Stop());
      expect(r.state.connState, ConnState.stopped);
    });

    test('Stop when already Stopped is a no-op', () {
      final r = StreamingPolicy.reduce(const StreamingState(), const Stop());
      expect(r.effects, isEmpty);
    });

    test('TokenPushDisabled stops streaming (poll only)', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const TokenPushDisabled());
      expect(r.state.connState, ConnState.stopped);
    });
  });

  group('Control events (stale guard + gate)', () {
    test('ControlPaused sets controlPaused, push down (no sync-mode change)',
        () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const ControlPaused(10));
      expect(r.state.controlPaused, isTrue);
      expect(r.state.lastControlTimestamp, 10);
      expect(r.state.pushUp, isFalse);
      expect(r.effects, contains(const NotifyPushDisabled()));
      // Control-driven, not connection-driven -> no EmitSyncModeChanged.
      expect(r.effects.whereType<EmitSyncModeChanged>().toList(), isEmpty);
    });

    test('ControlResumed resumes push iff occupancy not zero', () {
      final paused = connected(controlPaused: true, lastControl: 5);
      final r = StreamingPolicy.reduce(paused, const ControlResumed(6));
      expect(r.state.controlPaused, isFalse);
      expect(r.state.pushUp, isTrue);
      expect(r.effects, contains(const NotifyPushEnabled()));
      expect(r.effects, contains(const Fetch()));
      // Control-driven up-edge -> no EmitSyncModeChanged.
      expect(r.effects.whereType<EmitSyncModeChanged>(), isEmpty);
    });

    test('ControlResumed does NOT resume push while occupancy is zero', () {
      final s =
          connected(controlPaused: true, occupancyZero: true, lastControl: 5);
      final r = StreamingPolicy.reduce(s, const ControlResumed(6));
      expect(r.state.controlPaused, isFalse);
      expect(r.state.occupancyZero, isTrue);
      expect(r.state.pushUp, isFalse);
      expect(r.effects, isNot(contains(const NotifyPushEnabled())));
    });

    test('both controlPaused and occupancyZero must clear before push resumes',
        () {
      var s = connected(controlPaused: true, occupancyZero: true);
      // Clear control first: still down due to occupancy.
      var r = StreamingPolicy.reduce(s, const ControlResumed(1));
      expect(r.state.pushUp, isFalse);
      s = r.state;
      // Now clear occupancy: push comes up.
      r = StreamingPolicy.reduce(s, const OccupancyChanged(isZero: false));
      expect(r.state.pushUp, isTrue);
      expect(r.effects, contains(const NotifyPushEnabled()));
      // Occupancy-driven up-edge -> no EmitSyncModeChanged.
      expect(r.effects.whereType<EmitSyncModeChanged>(), isEmpty);
    });

    test('stale control timestamp is ignored (no state change)', () {
      final s = connected(lastControl: 100);
      final r = StreamingPolicy.reduce(s, const ControlPaused(50));
      expect(r.state, s);
      expect(r.effects, isEmpty);
    });

    test('equal control timestamp is ignored (duplicate)', () {
      final s = connected(lastControl: 100);
      final r = StreamingPolicy.reduce(s, const ControlPaused(100));
      expect(r.state, s);
      expect(r.effects, isEmpty);
    });

    test('ControlDisabled stops permanently -> poll only', () {
      final s = connected(lastControl: 1);
      final r = StreamingPolicy.reduce(s, const ControlDisabled(2));
      expect(r.state.connState, ConnState.stopped);
      expect(r.state.pushUp, isFalse);
      expect(r.effects, contains(const CloseCurrentSocket()));
      expect(r.effects, contains(const NotifyPushDisabled()));
      // Control-driven down-edge -> no EmitSyncModeChanged.
      expect(r.effects.whereType<EmitSyncModeChanged>(), isEmpty);
    });

    test('ControlReset invalidates token + reconnects', () {
      final s = connected(lastControl: 1);
      final r = StreamingPolicy.reduce(s, const ControlReset(2));
      expect(r.state.reconnecting, isTrue);
      expect(r.state.connState, ConnState.started);
      expect(
        r.effects,
        containsAllInOrder(const [InvalidateToken(), ScheduleReconnect()]),
      );
    });

    test('control events when not Started are no-ops', () {
      final r = StreamingPolicy.reduce(
          const StreamingState(), const ControlPaused(5));
      expect(r.effects, isEmpty);
    });
  });

  group('OccupancyChanged', () {
    test('occupancy -> zero drops push (no sync-mode change)', () {
      final s = connected();
      final r = StreamingPolicy.reduce(s, const OccupancyChanged(isZero: true));
      expect(r.state.occupancyZero, isTrue);
      expect(r.state.pushUp, isFalse);
      expect(r.effects, const [NotifyPushDisabled()]);
    });

    test('occupancy -> nonzero restores push + Fetch when other axes ok', () {
      final s = connected(occupancyZero: true);
      final r =
          StreamingPolicy.reduce(s, const OccupancyChanged(isZero: false));
      expect(r.state.pushUp, isTrue);
      expect(
          r.effects, containsAllInOrder(const [NotifyPushEnabled(), Fetch()]));
      // Occupancy-driven up-edge -> no EmitSyncModeChanged.
      expect(r.effects.whereType<EmitSyncModeChanged>(), isEmpty);
    });

    test('no change when occupancy value is unchanged', () {
      final s = connected();
      final r =
          StreamingPolicy.reduce(s, const OccupancyChanged(isZero: false));
      expect(r.state, s);
      expect(r.effects, isEmpty);
    });

    test('OccupancyChanged when not Started is a no-op', () {
      final r = StreamingPolicy.reduce(
          const StreamingState(), const OccupancyChanged(isZero: true));
      expect(r.effects, isEmpty);
    });
  });

  group('push edge is emitted exactly once', () {
    test('two consecutive down-gating events emit NotifyPushDisabled once', () {
      final s = connected();
      final r1 = StreamingPolicy.reduce(s, const ControlPaused(1));
      expect(r1.effects.whereType<NotifyPushDisabled>().length, 1);
      // Already down; occupancy zero must not re-emit disabled.
      final r2 = StreamingPolicy.reduce(
          r1.state, const OccupancyChanged(isZero: true));
      expect(r2.effects.whereType<NotifyPushDisabled>().length, 0);
    });
  });
}
