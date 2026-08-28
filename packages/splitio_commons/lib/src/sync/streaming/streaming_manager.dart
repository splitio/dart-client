import 'dart:async';

import 'package:splitio_commons/src/auth/auth.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';

import '../fetchers/flags_fetcher.dart';
import '../fetchers/memberships_fetcher.dart';
import 'clock.dart';
import 'effect_runner.dart';
import 'feed_update_router.dart';
import 'flag_update_strategy.dart';
import 'membership_payload_decoder.dart';
import 'membership_update_strategy.dart';
import 'notification_processor.dart';
import 'reconnect_scheduler.dart';
import 'sse_connection.dart';
import 'sse_uri_builder.dart';
import 'streaming_effect.dart';
import 'streaming_event.dart';
import 'streaming_policy.dart';
import 'streaming_state.dart';
import 'sync_delay_calculator.dart';

/// The concrete streaming effect runtime (spec §11): it OWNS the pure
/// [StreamingPolicy] FSM and executes the [StreamingEffect]s the policy returns.
///
/// It feeds lifecycle/notification events into [StreamingPolicy.reduce], runs
/// the resulting effects (open/close the SSE socket, schedule deduped reconnects
/// with exponential backoff, invalidate the auth token, trigger catch-up
/// fetches, emit push-up/down transitions), and routes incoming notifications
/// through the [NotificationProcessor] into the flag/membership strategy
/// handlers, applying seed-based jitter to unbounded/bounded membership fetches.
///
/// Push↔poll transitions are surfaced via [onPushEnabled]/[onPushDisabled] so a
/// higher coordinator (SyncManager, task 5.1) can stop/start polling.
///
/// All I/O is behind injected seams ([StreamingTransport], [AuthProvider],
/// fetchers, [Scheduler], [Clock]) so the manager is fully deterministic in
/// tests. It performs NO network I/O except through those seams.
class StreamingManager {
  final SplitLogger _log;

  late final FeedUpdateRouter _feedRouter;
  late final ReconnectScheduler _reconnectScheduler;
  late final SseConnection _connection;
  late final EffectRunner _effectRunner;

  StreamingState _state = const StreamingState();

  /// The last push-enabled JWT obtained at connect, used to compute the refresh
  /// delay from its `expiresAt` when [ScheduleTokenRefresh] runs.
  JwtCredential? _lastJwt;

  StreamingManager({
    required StreamingTransport transport,
    required AuthProvider authProvider,
    required FlagsFetcher flagsFetcher,
    required MembershipsFetcher membershipsFetcher,
    required InMemoryRuleStore ruleStore,
    required MembershipStore membershipStore,
    required Uri streamingBaseUri,
    required SplitLogger logger,
    RuleParser? ruleParser,
    MembershipPayloadDecoder decoder = const MembershipPayloadDecoder(),
    NotificationProcessor notificationProcessor = const NotificationProcessor(),
    SyncDelayCalculator syncDelayCalculator = const SyncDelayCalculator(),
    Scheduler scheduler = const SystemScheduler(),
    Clock clock = const SystemClock(),
    Target? target,
    List<String> Function()? matchingKeys,
    String ablyApiVersion = '1.1',
    void Function()? onPushEnabled,
    void Function()? onPushDisabled,
    void Function()? onConnectStarted,
    void Function()? onConnected,
    void Function()? onDisconnected,
    void Function(SyncMode mode, SyncModeChangeReason reason)?
        onSyncModeChanged,
  }) : _log = logger {
    _feedRouter = FeedUpdateRouter(
      flagsFetcher: flagsFetcher,
      membershipsFetcher: membershipsFetcher,
      flagStrategy:
          FlagUpdateStrategy(ruleStore: ruleStore, parser: ruleParser),
      membershipStrategy:
          MembershipUpdateStrategy(store: membershipStore, decoder: decoder),
      syncDelayCalculator: syncDelayCalculator,
      scheduler: scheduler,
      matchingKeys: matchingKeys ?? (() => const []),
      notificationProcessor: notificationProcessor,
      apply: _apply,
      logger: logger,
    );
    _reconnectScheduler = ReconnectScheduler(
      scheduler: scheduler,
      clock: clock,
      logger: logger,
      onReconnect: () => unawaited(_apply(const ReconnectTimerFired())),
      onRefresh: () => unawaited(_apply(const RefreshTokenTimerFired())),
    );
    _connection = SseConnection(
      transport: transport,
      authProvider: authProvider,
      uriBuilder: SseUriBuilder(
        streamingBaseUri: streamingBaseUri,
        ablyApiVersion: ablyApiVersion,
      ),
      target: target,
      logger: logger,
      apply: _apply,
      onMessage: _feedRouter.onMessage,
      onPushDisabled: () => onPushDisabled?.call(),
      onJwtObtained: (jwt) => _lastJwt = jwt,
      cancelTokenRefresh: _reconnectScheduler.cancelTokenRefresh,
      backoffAttempt: () => _reconnectScheduler.backoffAttempt,
      isStarted: () => _state.connState == ConnState.started,
    );
    _effectRunner = EffectRunner(
      connection: _connection,
      reconnectScheduler: _reconnectScheduler,
      feedRouter: _feedRouter,
      authProvider: authProvider,
      target: target,
      logger: logger,
      onPushEnabled: onPushEnabled,
      onPushDisabled: onPushDisabled,
      onConnectStarted: onConnectStarted,
      onConnected: onConnected,
      onDisconnected: onDisconnected,
      onSyncModeChanged: onSyncModeChanged,
      connectionUp: () =>
          _state.connState == ConnState.started &&
          !_state.connectionDown &&
          !_state.reconnecting,
      lastJwt: () => _lastJwt,
    );
  }

  /// The current FSM state (test/observation hook).
  StreamingState get state => _state;

  /// Whether push (streaming) is currently up.
  bool get isPushUp => _state.pushUp;

  /// Begins streaming: drives the FSM `Start` and executes its effects.
  Future<void> start() => _apply(const Start());

  /// Stops streaming permanently for this request. Idempotent.
  Future<void> stop() => _apply(const Stop());

  // --- FSM driving ----------------------------------------------------------

  /// Reduces [event] through the pure policy, commits the next state, and
  /// executes the resulting effects. Never throws — effect execution errors are
  /// caught so a bad notification/fetch cannot kill the manager.
  Future<void> _apply(StreamingEvent event) async {
    final ReduceResult result;
    final prev = _state;
    try {
      result = StreamingPolicy.reduce(_state, event);
    } catch (e) {
      _log.error('StreamingManager: reduce failed for $event', e);
      return;
    }
    _state = result.state;
    if (_log.isVerboseEnabled) {
      _log.verbose('StreamingManager: event $event: '
          '$prev -> ${result.state}'
          '${result.effects.isEmpty ? '' : ' effects=${result.effects}'}');
    } else if (_log.isDebugEnabled && prev.pushUp != result.state.pushUp) {
      _log.debug(
          'StreamingManager: push ${result.state.pushUp ? 'UP' : 'DOWN'} '
          '(via $event)');
    }
    for (final effect in result.effects) {
      await _effectRunner.execute(effect);
    }
  }
}
