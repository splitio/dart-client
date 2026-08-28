/// Connection lifecycle state (spec §11.1).
///
/// The `Reconnecting`/`PollingFallback` boxes in the §11.2 diagram are NOT
/// separate [ConnState]s — they are captured by the [StreamingState.reconnecting]
/// flag and the derived [StreamingState.pushUp] gate respectively.
enum ConnState { stopped, started, paused }

/// Immutable state of the streaming policy FSM (spec §11.1).
///
/// [pushUp] is *derived* from the 3-axis gate (§11.2) and is not stored, so it
/// can never drift from the underlying flags.
final class StreamingState {
  final ConnState connState;
  final bool controlPaused;
  final bool occupancyZero;
  final bool connectionDown;
  final int consecutiveFailures;
  final bool reconnecting;
  final int lastControlTimestamp;

  const StreamingState({
    this.connState = ConnState.stopped,
    this.controlPaused = false,
    this.occupancyZero = false,
    // We are not connected until the first SocketOpened; the connection axis
    // starts "down" so the initial connect produces a push up-edge.
    this.connectionDown = true,
    this.consecutiveFailures = 0,
    this.reconnecting = false,
    this.lastControlTimestamp = 0,
  });

  /// The 3-axis push gate (spec §11.2): push is up only when no axis blocks it.
  bool get pushUp => !controlPaused && !occupancyZero && !connectionDown;

  StreamingState copyWith({
    ConnState? connState,
    bool? controlPaused,
    bool? occupancyZero,
    bool? connectionDown,
    int? consecutiveFailures,
    bool? reconnecting,
    int? lastControlTimestamp,
  }) {
    return StreamingState(
      connState: connState ?? this.connState,
      controlPaused: controlPaused ?? this.controlPaused,
      occupancyZero: occupancyZero ?? this.occupancyZero,
      connectionDown: connectionDown ?? this.connectionDown,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      reconnecting: reconnecting ?? this.reconnecting,
      lastControlTimestamp: lastControlTimestamp ?? this.lastControlTimestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StreamingState &&
      other.connState == connState &&
      other.controlPaused == controlPaused &&
      other.occupancyZero == occupancyZero &&
      other.connectionDown == connectionDown &&
      other.consecutiveFailures == consecutiveFailures &&
      other.reconnecting == reconnecting &&
      other.lastControlTimestamp == lastControlTimestamp;

  @override
  int get hashCode => Object.hash(
        connState,
        controlPaused,
        occupancyZero,
        connectionDown,
        consecutiveFailures,
        reconnecting,
        lastControlTimestamp,
      );

  @override
  String toString() => 'StreamingState(connState: $connState, '
      'controlPaused: $controlPaused, occupancyZero: $occupancyZero, '
      'connectionDown: $connectionDown, '
      'consecutiveFailures: $consecutiveFailures, '
      'reconnecting: $reconnecting, '
      'lastControlTimestamp: $lastControlTimestamp, pushUp: $pushUp)';
}
