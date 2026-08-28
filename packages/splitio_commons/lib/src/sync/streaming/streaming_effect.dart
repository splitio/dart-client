/// Side effects returned by the pure [StreamingPolicy] FSM (spec §11.1).
///
/// The policy never executes these; the effect runtime (Task 4.7) owns all
/// mechanism (socket I/O, timers, token fetch, event emission).
sealed class StreamingEffect {
  const StreamingEffect();
}

/// Open a fresh streaming socket (pulls a credential at (re)connect).
final class OpenSocket extends StreamingEffect {
  const OpenSocket();
  @override
  bool operator ==(Object other) => other is OpenSocket;
  @override
  int get hashCode => (OpenSocket).hashCode;
}

/// Close the current streaming socket, if any.
final class CloseCurrentSocket extends StreamingEffect {
  const CloseCurrentSocket();
  @override
  bool operator ==(Object other) => other is CloseCurrentSocket;
  @override
  int get hashCode => (CloseCurrentSocket).hashCode;
}

/// Schedule a (deduped, backed-off) reconnect attempt.
final class ScheduleReconnect extends StreamingEffect {
  const ScheduleReconnect();
  @override
  bool operator ==(Object other) => other is ScheduleReconnect;
  @override
  int get hashCode => (ScheduleReconnect).hashCode;
}

/// Reset the reconnect backoff to its initial interval.
final class ResetBackoff extends StreamingEffect {
  const ResetBackoff();
  @override
  bool operator ==(Object other) => other is ResetBackoff;
  @override
  int get hashCode => (ResetBackoff).hashCode;
}

/// Invalidate the cached auth token (forces a fresh JWT next connect).
final class InvalidateToken extends StreamingEffect {
  const InvalidateToken();
  @override
  bool operator ==(Object other) => other is InvalidateToken;
  @override
  int get hashCode => (InvalidateToken).hashCode;
}

/// Schedule the single proactive token-refresh task (§11.3): the runtime arms a
/// timer to fire at `expiresAt − refreshLeadTime` (10 min before expiry) so the
/// streaming token is refreshed before it expires. Deduped (cancel-then-schedule)
/// — at most one may be pending. Emitted on every successful socket open so a
/// reconnect always rearms the timer from the fresh credential's expiry.
final class ScheduleTokenRefresh extends StreamingEffect {
  const ScheduleTokenRefresh();
  @override
  bool operator ==(Object other) => other is ScheduleTokenRefresh;
  @override
  int get hashCode => (ScheduleTokenRefresh).hashCode;
}

/// Cancel the pending proactive token-refresh task (§11.3). Emitted whenever the
/// streaming connection goes down or stops, so a stale refresh never fires
/// against a torn-down connection; a fresh one is rescheduled on the next
/// successful connect.
final class CancelTokenRefresh extends StreamingEffect {
  const CancelTokenRefresh();
  @override
  bool operator ==(Object other) => other is CancelTokenRefresh;
  @override
  int get hashCode => (CancelTokenRefresh).hashCode;
}

/// Notify that push (streaming) is now up — leave poll fallback.
final class NotifyPushEnabled extends StreamingEffect {
  const NotifyPushEnabled();
  @override
  bool operator ==(Object other) => other is NotifyPushEnabled;
  @override
  int get hashCode => (NotifyPushEnabled).hashCode;
}

/// Notify that push is now down — fall back to polling.
final class NotifyPushDisabled extends StreamingEffect {
  const NotifyPushDisabled();
  @override
  bool operator ==(Object other) => other is NotifyPushDisabled;
  @override
  int get hashCode => (NotifyPushDisabled).hashCode;
}

/// Trigger a catch-up synchronization fetch.
final class Fetch extends StreamingEffect {
  const Fetch();
  @override
  bool operator ==(Object other) => other is Fetch;
  @override
  int get hashCode => (Fetch).hashCode;
}

/// Emit the "connection attempt started" lifecycle event.
final class EmitConnectStarted extends StreamingEffect {
  const EmitConnectStarted();
  @override
  bool operator ==(Object other) => other is EmitConnectStarted;
  @override
  int get hashCode => (EmitConnectStarted).hashCode;
}

/// Emit the "connected" lifecycle event.
final class EmitConnected extends StreamingEffect {
  const EmitConnected();
  @override
  bool operator ==(Object other) => other is EmitConnected;
  @override
  int get hashCode => (EmitConnected).hashCode;
}

/// Emit the "disconnected" lifecycle event.
final class EmitDisconnected extends StreamingEffect {
  const EmitDisconnected();
  @override
  bool operator ==(Object other) => other is EmitDisconnected;
  @override
  int get hashCode => (EmitDisconnected).hashCode;
}

/// The sync mode the SDK is switching to.
enum SyncMode { streaming, polling }

/// Why the sync mode changed. Only connection-driven edges emit
/// [EmitSyncModeChanged] (spec §11.2).
enum SyncModeChangeReason { streamingConnected, streamingDisconnected }

/// Emit a user-facing sync-mode-changed event for connection-driven edges.
final class EmitSyncModeChanged extends StreamingEffect {
  final SyncMode to;
  final SyncModeChangeReason reason;
  const EmitSyncModeChanged({required this.to, required this.reason});

  @override
  bool operator ==(Object other) =>
      other is EmitSyncModeChanged && other.to == to && other.reason == reason;

  @override
  int get hashCode => Object.hash(to, reason);
}
