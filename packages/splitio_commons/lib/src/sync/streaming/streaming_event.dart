/// Events consumed by the pure [StreamingPolicy] FSM (spec §11.1).
///
/// Events are modeled as *already-parsed*: mapping a wire `controlType` to a
/// [ControlPaused]/[ControlResumed]/[ControlDisabled]/[ControlReset] event is
/// the `NotificationProcessor`'s job (§11.3). The FSM only decides transitions
/// and the stale-timestamp guard from the timestamps already on the events.
sealed class StreamingEvent {
  const StreamingEvent();
}

/// Begin streaming (Stopped → Started).
final class Start extends StreamingEvent {
  const Start();
}

/// Stop streaming permanently for this request (any → Stopped).
final class Stop extends StreamingEvent {
  const Stop();
}

/// Pause streaming, keeping it resumable (Started → Paused).
final class Pause extends StreamingEvent {
  const Pause();
}

/// Resume a paused stream (Paused → Started).
final class Resume extends StreamingEvent {
  const Resume();
}

/// The underlying socket successfully opened (self-loop on Started).
final class SocketOpened extends StreamingEvent {
  const SocketOpened();
}

/// The underlying socket errored.
///
/// [retryable] `true` schedules a reconnect; `false` stops streaming.
final class SocketError extends StreamingEvent {
  final bool retryable;
  const SocketError({required this.retryable});

  @override
  bool operator ==(Object other) =>
      other is SocketError && other.retryable == retryable;

  @override
  int get hashCode => retryable.hashCode;
}

/// The scheduled reconnect timer fired; the FSM should re-open the socket.
final class ReconnectTimerFired extends StreamingEvent {
  const ReconnectTimerFired();
}

/// The proactive token-refresh timer fired (§11.3): the streaming token is
/// approaching expiry, so the FSM MUST invalidate it and reconnect to pull a
/// fresh JWT. Reduces like a `ControlReset` (`InvalidateToken` + reconnect).
final class RefreshTokenTimerFired extends StreamingEvent {
  const RefreshTokenTimerFired();
}

/// The auth credential reports `pushEnabled == false` → poll only.
final class TokenPushDisabled extends StreamingEvent {
  const TokenPushDisabled();
}

/// An SSE `error` frame was received.
///
/// [isTokenError] `true` (HTTP 401 / code 40140-40149) triggers token
/// invalidation + reconnect; `false` is a non-retryable error → stop.
final class ErrorFrame extends StreamingEvent {
  final bool isTokenError;
  const ErrorFrame({required this.isTokenError});

  @override
  bool operator ==(Object other) =>
      other is ErrorFrame && other.isTokenError == isTokenError;

  @override
  int get hashCode => isTokenError.hashCode;
}

/// Base for wire-`CONTROL` events; all carry a [timestamp] for stale guarding.
sealed class ControlEvent extends StreamingEvent {
  final int timestamp;
  const ControlEvent(this.timestamp);
}

/// `STREAMING_PAUSED` → `controlPaused = true` → poll fallback.
final class ControlPaused extends ControlEvent {
  const ControlPaused(super.timestamp);

  @override
  bool operator ==(Object other) =>
      other is ControlPaused && other.timestamp == timestamp;

  @override
  int get hashCode => timestamp.hashCode;
}

/// `STREAMING_RESUMED` → `controlPaused = false` → push up iff not empty.
final class ControlResumed extends ControlEvent {
  const ControlResumed(super.timestamp);

  @override
  bool operator ==(Object other) =>
      other is ControlResumed && other.timestamp == timestamp;

  @override
  int get hashCode => timestamp.hashCode;
}

/// `STREAMING_DISABLED` → stop streaming permanently → poll only.
final class ControlDisabled extends ControlEvent {
  const ControlDisabled(super.timestamp);

  @override
  bool operator ==(Object other) =>
      other is ControlDisabled && other.timestamp == timestamp;

  @override
  int get hashCode => timestamp.hashCode;
}

/// `STREAMING_RESET` → force reconnect + re-auth (invalidate token).
final class ControlReset extends ControlEvent {
  const ControlReset(super.timestamp);

  @override
  bool operator ==(Object other) =>
      other is ControlReset && other.timestamp == timestamp;

  @override
  int get hashCode => timestamp.hashCode;
}

/// Occupancy metric changed. [isZero] `true` gates push down.
final class OccupancyChanged extends StreamingEvent {
  final bool isZero;
  const OccupancyChanged({required this.isZero});

  @override
  bool operator ==(Object other) =>
      other is OccupancyChanged && other.isZero == isZero;

  @override
  int get hashCode => isZero.hashCode;
}
