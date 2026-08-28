import 'package:splitio_commons/src/auth/auth.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';

import 'feed_update_router.dart';
import 'reconnect_scheduler.dart';
import 'sse_connection.dart';
import 'streaming_effect.dart';

/// Executes the [StreamingEffect]s produced by the pure [StreamingPolicy] FSM
/// (spec §11): it delegates each effect to the owning collaborator — the SSE
/// socket, the reconnect/token-refresh scheduler, the auth provider, the
/// catch-up fetcher — and fires the push↔poll / lifecycle callbacks.
///
/// It performs no FSM reduction of its own; the [StreamingManager] drives the
/// policy and hands the resulting effects here one at a time. Every effect is
/// guarded so a failing effect cannot kill the manager.
class EffectRunner {
  final SseConnection _connection;
  final ReconnectScheduler _reconnectScheduler;
  final FeedUpdateRouter _feedRouter;
  final AuthProvider _authProvider;
  final Target? _target;
  final SplitLogger _log;

  final void Function()? _onPushEnabled;
  final void Function()? _onPushDisabled;
  final void Function()? _onConnectStarted;
  final void Function()? _onConnected;
  final void Function()? _onDisconnected;
  final void Function(SyncMode mode, SyncModeChangeReason reason)?
      _onSyncModeChanged;

  /// Whether the streaming connection is genuinely up (gates arming the
  /// proactive token-refresh timer, §11.3).
  final bool Function() _connectionUp;

  /// The last push-enabled credential, used to compute the refresh delay.
  final JwtCredential? Function() _lastJwt;

  const EffectRunner({
    required SseConnection connection,
    required ReconnectScheduler reconnectScheduler,
    required FeedUpdateRouter feedRouter,
    required AuthProvider authProvider,
    required Target? target,
    required SplitLogger logger,
    void Function()? onPushEnabled,
    void Function()? onPushDisabled,
    void Function()? onConnectStarted,
    void Function()? onConnected,
    void Function()? onDisconnected,
    void Function(SyncMode mode, SyncModeChangeReason reason)?
        onSyncModeChanged,
    required bool Function() connectionUp,
    required JwtCredential? Function() lastJwt,
  })  : _connection = connection,
        _reconnectScheduler = reconnectScheduler,
        _feedRouter = feedRouter,
        _authProvider = authProvider,
        _target = target,
        _log = logger,
        _onPushEnabled = onPushEnabled,
        _onPushDisabled = onPushDisabled,
        _onConnectStarted = onConnectStarted,
        _onConnected = onConnected,
        _onDisconnected = onDisconnected,
        _onSyncModeChanged = onSyncModeChanged,
        _connectionUp = connectionUp,
        _lastJwt = lastJwt;

  Future<void> execute(StreamingEffect effect) async {
    try {
      switch (effect) {
        case OpenSocket():
          await _connection.open();
        case CloseCurrentSocket():
          _reconnectScheduler.cancelReconnect();
          await _connection.close();
        case ScheduleReconnect():
          _reconnectScheduler.scheduleReconnect();
        case ResetBackoff():
          _reconnectScheduler.resetBackoff();
        case InvalidateToken():
          _authProvider.invalidate(_target);
        case ScheduleTokenRefresh():
          _reconnectScheduler.scheduleTokenRefresh(
            connectionUp: _connectionUp(),
            jwt: _lastJwt(),
          );
        case CancelTokenRefresh():
          _reconnectScheduler.cancelTokenRefresh();
        case NotifyPushEnabled():
          _onPushEnabled?.call();
        case NotifyPushDisabled():
          _onPushDisabled?.call();
        case Fetch():
          _feedRouter.catchUp();
        case EmitConnectStarted():
          _onConnectStarted?.call();
        case EmitConnected():
          _onConnected?.call();
        case EmitDisconnected():
          _onDisconnected?.call();
        case EmitSyncModeChanged(:final to, :final reason):
          _onSyncModeChanged?.call(to, reason);
      }
    } catch (e, st) {
      _log.error('StreamingManager: effect $effect failed', '$e\n$st');
    }
  }
}
