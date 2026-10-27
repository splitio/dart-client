import 'streaming_effect.dart';
import 'streaming_event.dart';
import 'streaming_state.dart';

/// Result of a single [StreamingPolicy.reduce] step: the next [state] and the
/// ordered list of [effects] the runtime must execute.
final class ReduceResult {
  final StreamingState state;
  final List<StreamingEffect> effects;
  const ReduceResult(this.state, this.effects);
}

/// Pure, zero-I/O finite state machine for the streaming lifecycle (spec §11).
///
/// [reduce] is deterministic: it has NO I/O, NO timers and NO async. It maps a
/// `(state, event)` pair to a `(state, effects)` result. The effect runtime
/// (Task 4.7) owns all mechanism (socket I/O, timers, token fetch, emission).
///
/// The push↔poll fallback is DERIVED from the 3-axis gate
/// `pushUp = !controlPaused && !occupancyZero && !connectionDown` (§11.2): an
/// edge on `pushUp` emits [NotifyPushEnabled]/[NotifyPushDisabled], plus an
/// [EmitSyncModeChanged] for connection-driven edges only.
// LOC-exemption: pure FSM reducer — cohesive (state,event)→(state,effects) mapping, tiny transitions, no branching depth; splitting would scatter transitions that must be read as a set. Approved 2026-07-22.
abstract final class StreamingPolicy {
  /// Applies [event] to [state], returning the next state and effects.
  static ReduceResult reduce(StreamingState state, StreamingEvent event) {
    switch (event) {
      case Start():
        return _onStart(state);
      case Stop():
        return _stop(state);
      case Pause():
        return _onPause(state);
      case Resume():
        return _onResume(state);
      case SocketOpened():
        return _onSocketOpened(state);
      case SocketError(:final retryable):
        return _onSocketError(state, retryable);
      case ReconnectTimerFired():
        return _onReconnectTimerFired(state);
      case TokenPushDisabled():
        return _stop(state);
      case ErrorFrame(:final isTokenError):
        return _onErrorFrame(state, isTokenError);
      case RefreshTokenTimerFired():
        return _onRefreshTokenTimerFired(state);
      case ControlPaused(:final timestamp):
        return _onControl(state, timestamp, _applyControlPaused);
      case ControlResumed(:final timestamp):
        return _onControl(state, timestamp, _applyControlResumed);
      case ControlDisabled(:final timestamp):
        return _onControl(state, timestamp, _applyControlDisabled);
      case ControlReset(:final timestamp):
        return _onControl(state, timestamp, _applyControlReset);
      case OccupancyChanged(:final isZero):
        return _onOccupancyChanged(state, isZero);
    }
  }

  // --- Connection lifecycle events ------------------------------------------

  static ReduceResult _onStart(StreamingState s) {
    if (s.connState != ConnState.stopped) return _noop(s);
    final next = s.copyWith(
      connState: ConnState.started,
      reconnecting: false,
      consecutiveFailures: 0,
    );
    return _finalize(s, next, const [EmitConnectStarted(), OpenSocket()]);
  }

  /// Stop permanently for this request (also `Stop` / `TokenPushDisabled`).
  static ReduceResult _stop(StreamingState s) {
    if (s.connState == ConnState.stopped) return _noop(s);
    final next = s.copyWith(
      connState: ConnState.stopped,
      connectionDown: true,
      reconnecting: false,
      consecutiveFailures: 0,
    );
    return _finalize(s, next, const [CloseCurrentSocket()]);
  }

  static ReduceResult _onPause(StreamingState s) {
    if (s.connState != ConnState.started) return _noop(s);
    final next = s.copyWith(
      connState: ConnState.paused,
      connectionDown: true,
      reconnecting: false,
    );
    return _finalize(s, next, const [CloseCurrentSocket()]);
  }

  static ReduceResult _onResume(StreamingState s) {
    if (s.connState != ConnState.paused) return _noop(s);
    final next = s.copyWith(
      connState: ConnState.started,
      reconnecting: false,
    );
    return _finalize(s, next, const [EmitConnectStarted(), OpenSocket()]);
  }

  static ReduceResult _onSocketOpened(StreamingState s) {
    if (s.connState != ConnState.started) return _noop(s);
    final next = s.copyWith(
      connectionDown: false,
      consecutiveFailures: 0,
      // Optimistic reset: assume non-zero occupancy on connect; a subsequent
      // OccupancyChanged(isZero: true) corrects it if the channel is empty
      // (§11.3).
      occupancyZero: false,
      reconnecting: false,
    );
    // Every successful open (re)schedules the single proactive token refresh
    // from the just-connected credential's expiry (§11.3). The runtime dedups
    // (cancel-then-schedule) so a reconnect always replaces any prior timer.
    return _finalize(s, next, const [ResetBackoff(), ScheduleTokenRefresh()],
        connectionDriven: true);
  }

  static ReduceResult _onSocketError(StreamingState s, bool retryable) {
    if (s.connState != ConnState.started) return _noop(s);
    if (!retryable) return _stop(s);
    return _onRetryableFailure(s);
  }

  static ReduceResult _onReconnectTimerFired(StreamingState s) {
    if (s.connState != ConnState.started || !s.reconnecting) return _noop(s);
    final next = s.copyWith(reconnecting: false);
    return _finalize(s, next, const [EmitConnectStarted(), OpenSocket()]);
  }

  static ReduceResult _onErrorFrame(StreamingState s, bool isTokenError) {
    if (s.connState != ConnState.started) return _noop(s);
    if (!isTokenError) return _stop(s);
    // Token error (401 / 40140-40149) is a retryable failure (§11.3):
    // additionally invalidate the cached credential so the next connect
    // re-auths.
    return _onRetryableFailure(s, invalidateToken: true);
  }

  /// Every retryable failure — `SocketError(retryable: true)` or a
  /// token-error `ErrorFrame` — follows the same path (§11.3): close the
  /// current socket, drop the connection axis (`connectionDown = true`),
  /// and schedule the **next** backoff step, so consecutive failures grow
  /// the delay. Token errors additionally invalidate the cached credential.
  ///
  /// `connectionDown` is now set UNCONDITIONALLY on every retryable failure
  /// (the old ">= 2 consecutive failures" threshold is removed per spec).
  /// [_finalize] is told `forcePushDownNotify: true` so `NotifyPushDisabled`
  /// fires even when there is no push-gate EDGE — notably on the very first
  /// failure, when `connectionDown`/`pushUp` already started down and no
  /// successful connect has ever happened, so there would otherwise never be
  /// an edge to drive poll fallback.
  static ReduceResult _onRetryableFailure(
    StreamingState s, {
    bool invalidateToken = false,
  }) {
    final next = s.copyWith(
      reconnecting: true,
      consecutiveFailures: s.consecutiveFailures + 1,
      connectionDown: true,
    );
    final direct = <StreamingEffect>[const CloseCurrentSocket()];
    if (invalidateToken) direct.add(const InvalidateToken());
    direct.add(const ScheduleReconnect());
    return _finalize(s, next, direct,
        connectionDriven: true, forcePushDownNotify: true);
  }

  /// The proactive token-refresh timer fired (§11.3): re-auth + reconnect,
  /// exactly like a `ControlReset`. Ignored unless we are actively streaming.
  static ReduceResult _onRefreshTokenTimerFired(StreamingState s) {
    if (s.connState != ConnState.started) return _noop(s);
    final next = s.copyWith(reconnecting: true);
    return _finalize(s, next, const [InvalidateToken(), ScheduleReconnect()]);
  }

  // --- Control events (stale-timestamp guarded) -----------------------------

  static ReduceResult _onControl(
    StreamingState s,
    int timestamp,
    StreamingState Function(StreamingState) apply,
  ) {
    if (s.connState != ConnState.started) return _noop(s);
    // Stale (or duplicate) control notifications MUST be ignored (§11.3).
    if (timestamp <= s.lastControlTimestamp) return _noop(s);
    final applied = apply(s).copyWith(lastControlTimestamp: timestamp);
    return _finalizeControl(s, applied);
  }

  static StreamingState _applyControlPaused(StreamingState s) =>
      s.copyWith(controlPaused: true);

  static StreamingState _applyControlResumed(StreamingState s) =>
      s.copyWith(controlPaused: false);

  static StreamingState _applyControlDisabled(StreamingState s) => s.copyWith(
        connState: ConnState.stopped,
        connectionDown: true,
        reconnecting: false,
        consecutiveFailures: 0,
      );

  static StreamingState _applyControlReset(StreamingState s) =>
      s.copyWith(reconnecting: true);

  /// Control transitions carry their own direct effects derived from the shape
  /// of the applied state, then run the shared edge machinery.
  static ReduceResult _finalizeControl(
      StreamingState prev, StreamingState next) {
    final direct = <StreamingEffect>[];
    if (next.connState == ConnState.stopped) {
      // ControlDisabled: close the socket permanently.
      direct.add(const CloseCurrentSocket());
    } else if (next.reconnecting && !prev.reconnecting) {
      // ControlReset: force re-auth + reconnect.
      direct
        ..add(const InvalidateToken())
        ..add(const ScheduleReconnect());
    }
    return _finalize(prev, next, direct);
  }

  // --- Occupancy ------------------------------------------------------------

  static ReduceResult _onOccupancyChanged(StreamingState s, bool isZero) {
    if (s.connState != ConnState.started) return _noop(s);
    if (s.occupancyZero == isZero) return _noop(s);
    final next = s.copyWith(occupancyZero: isZero);
    return _finalize(s, next, const []);
  }

  // --- Shared edge machinery ------------------------------------------------

  static ReduceResult _noop(StreamingState s) => ReduceResult(s, const []);

  /// Appends connection-lifecycle and push-gate edge effects to [direct].
  ///
  /// - A `connectionDown` false→true edge emits [EmitDisconnected]; true→false
  ///   emits [EmitConnected].
  /// - A `pushUp` edge emits [NotifyPushEnabled]/[NotifyPushDisabled]. When the
  ///   edge is a connection-axis change AND [connectionDriven] is true (i.e. the
  ///   caller is a socket connection event — [SocketOpened]/[SocketError]), it
  ///   also emits [EmitSyncModeChanged] (§11.2). User commands, control
  ///   notifications and occupancy changes never emit it. A push up-edge
  ///   additionally emits a catch-up [Fetch] (§11.3).
  /// - [forcePushDownNotify] (set by every retryable failure, §11.3): when
  ///   `true` and the push gate is down in [next] but there was no genuine
  ///   `pushUp` EDGE (e.g. the connection started — and still is — down, so
  ///   this is the first failure before any successful connect), a
  ///   [NotifyPushDisabled] is still emitted so poll fallback is guaranteed
  ///   to engage. Receivers MUST treat it idempotently. This never emits a
  ///   duplicate when a genuine edge already added one.
  static ReduceResult _finalize(
    StreamingState prev,
    StreamingState next,
    List<StreamingEffect> direct, {
    bool connectionDriven = false,
    bool forcePushDownNotify = false,
  }) {
    final effects = <StreamingEffect>[...direct];

    final connEdge = prev.connectionDown != next.connectionDown;
    if (!prev.connectionDown && next.connectionDown) {
      // Connection down-edge: stop the proactive token refresh so it never
      // fires against a torn-down connection (§11.3).
      effects
        ..add(const EmitDisconnected())
        ..add(const CancelTokenRefresh());
    } else if (prev.connectionDown && !next.connectionDown) {
      effects.add(const EmitConnected());
    }

    final pushEdgeUp = !prev.pushUp && next.pushUp;
    final pushEdgeDown = prev.pushUp && !next.pushUp;

    if (pushEdgeUp) {
      effects.add(const NotifyPushEnabled());
      if (connEdge && connectionDriven) {
        effects.add(const EmitSyncModeChanged(
          to: SyncMode.streaming,
          reason: SyncModeChangeReason.streamingConnected,
        ));
      }
      effects.add(const Fetch());
    } else if (pushEdgeDown) {
      effects.add(const NotifyPushDisabled());
      if (connEdge && connectionDriven) {
        effects.add(const EmitSyncModeChanged(
          to: SyncMode.polling,
          reason: SyncModeChangeReason.streamingDisconnected,
        ));
      }
    } else if (forcePushDownNotify && !next.pushUp) {
      effects.add(const NotifyPushDisabled());
    }

    return ReduceResult(next, effects);
  }
}
