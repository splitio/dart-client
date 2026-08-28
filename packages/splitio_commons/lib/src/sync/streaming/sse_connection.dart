import 'dart:async';

import 'package:splitio_commons/src/auth/auth.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';

import 'event_source_client.dart';
import 'sse_uri_builder.dart';
import 'streaming_event.dart';

/// Owns the SSE socket lifecycle for streaming (spec §10.3, §11.3): opening a
/// connection (auth → connect → status classification), tearing it down, and
/// the generation-counter TOCTOU guards that keep concurrent reconnects from
/// clobbering each other.
///
/// It performs NO FSM/scheduler logic of its own: it drives the FSM back
/// through the injected [apply] callback and defers to the injected seams for
/// everything else. This keeps the subtle `_connectGeneration` race handling in
/// one place while leaving policy in the [StreamingManager].
class SseConnection {
  final StreamingTransport _transport;
  final AuthProvider _authProvider;
  final SseUriBuilder _uriBuilder;
  final Target? _target;
  final SplitLogger _log;

  final Future<void> Function(StreamingEvent event) _apply;
  final Future<void> Function(RawNotification notification) _onMessage;
  final void Function() _onPushDisabled;
  final void Function(JwtCredential jwt) _onJwtObtained;
  final void Function() _cancelTokenRefresh;
  final int Function() _backoffAttempt;
  final bool Function() _isStarted;

  EventSourceClient? _client;
  bool _opening = false;
  int _connectGeneration = 0;

  SseConnection({
    required StreamingTransport transport,
    required AuthProvider authProvider,
    required SseUriBuilder uriBuilder,
    required Target? target,
    required SplitLogger logger,
    required Future<void> Function(StreamingEvent event) apply,
    required Future<void> Function(RawNotification notification) onMessage,
    required void Function() onPushDisabled,
    required void Function(JwtCredential jwt) onJwtObtained,
    required void Function() cancelTokenRefresh,
    required int Function() backoffAttempt,
    required bool Function() isStarted,
  })  : _transport = transport,
        _authProvider = authProvider,
        _uriBuilder = uriBuilder,
        _target = target,
        _log = logger,
        _apply = apply,
        _onMessage = onMessage,
        _onPushDisabled = onPushDisabled,
        _onJwtObtained = onJwtObtained,
        _cancelTokenRefresh = cancelTokenRefresh,
        _backoffAttempt = backoffAttempt,
        _isStarted = isStarted;

  Future<void> open() async {
    // Reconnect dedup (§11.3): never open a second socket while one is opening.
    if (_opening) {
      _log.verbose('StreamingManager: open requested while already opening — '
          'skipped (dedup)');
      return;
    }
    _opening = true;
    // Claim a fresh connect generation. Any reconnect firing during one of the
    // async gaps below (the credential fetch, the socket connect) bumps this
    // counter via its own open() call, so a superseded in-flight connect
    // can detect that it lost the race and bail without assigning a stale
    // _client or opening a second socket (TOCTOU guard, §11.3).
    final generation = ++_connectGeneration;
    try {
      // Tear down any prior socket before opening a fresh one.
      await close();

      _log.debug('StreamingManager: opening SSE socket (attempt '
          '${_backoffAttempt()}, generation $generation)');
      final credential = await _authProvider.credential(_target);
      // A newer connect superseded us while the credential fetch was in flight:
      // abandon this attempt so we never overwrite the newer _client.
      if (generation != _connectGeneration) {
        _log.verbose('StreamingManager: connect generation $generation '
            'superseded during auth — abandoning');
        return;
      }
      final jwt = credential is JwtCredential ? credential : null;

      // pushEnabled == false MUST mean poll only (§11.3): do NOT connect; drive
      // the FSM to push-disabled so the poll-fallback callback fires.
      if (jwt == null || !jwt.pushEnabled || jwt.channels.isEmpty) {
        _log.debug('StreamingManager: credential has no push (pushEnabled='
            '${jwt?.pushEnabled}, channels=${jwt?.channels.length ?? 0}) — '
            'poll only');
        // pushEnabled == false means poll only: the FSM `Stop` produces no
        // push-gate edge (push was never up), so signal the poll fallback
        // directly for the coordinator (SyncManager) to start polling.
        _onPushDisabled();
        await _apply(const TokenPushDisabled());
        return;
      }

      // Remember the credential so a subsequent ScheduleTokenRefresh (fired on
      // the connection up-edge) can compute the refresh delay from its expiry.
      _onJwtObtained(jwt);

      final uri = _uriBuilder.build(jwt);
      _log.debug(
          'StreamingManager: connecting to ${_uriBuilder.redactToken(uri)} '
          '(${jwt.channels.length} channel(s))');
      if (_log.isVerboseEnabled) {
        _log.verbose('StreamingManager: channels=${jwt.channels.join(',')}');
      }
      final headers = <String, String>{
        'Accept': 'text/event-stream',
      };

      final client = EventSourceClient(transport: _transport);
      _client = client;

      await client.connect(
        uri,
        headers,
        onMessage: (n) => unawaited(_onMessage(n)),
        onError: (e, st) =>
            _log.warning('StreamingManager: SSE frame error (skipped): $e'),
        onDone: () => unawaited(_onSocketDone(generation)),
      );

      // A newer connect superseded us during the connect handshake: close this
      // now-orphaned socket and bail without driving the FSM off stale status.
      if (generation != _connectGeneration) {
        await client.close();
        return;
      }

      // Map the initial connect status (§10.3) to an FSM event.
      final status = client.statusCode ?? 0;
      _log.debug('StreamingManager: SSE connect status $status');
      await _applyConnectStatus(status);
    } catch (e, st) {
      _log.warning('StreamingManager: connect failed: $e');
      _log.debug('$st');
      // Only drive the FSM error path if we are still the current connect;
      // otherwise a newer attempt owns the lifecycle.
      if (generation == _connectGeneration) {
        await _apply(const SocketError(retryable: true));
      }
    } finally {
      // Always release the opening latch for the CURRENT generation. A
      // superseded attempt must not clear a newer attempt's latch.
      if (generation == _connectGeneration) _opening = false;
    }
  }

  Future<void> _applyConnectStatus(int status) async {
    final action = classifyStatus(status);
    switch (action) {
      case HttpStatusAction.apply:
      case HttpStatusAction.notModified:
        await _apply(const SocketOpened());
      case HttpStatusAction.authFailure:
        // 401/403 → token error → invalidate + reconnect.
        await _apply(const ErrorFrame(isTokenError: true));
      case HttpStatusAction.transientRetry:
        await _apply(const SocketError(retryable: true));
      case HttpStatusAction.uriTooLong:
      case HttpStatusAction.doNotRetry:
        await _apply(const SocketError(retryable: false));
    }
  }

  Future<void> _onSocketDone(int generation) async {
    // Ignore a done from a superseded connection.
    if (generation != _connectGeneration) return;
    if (!_isStarted()) return;
    _log.debug('StreamingManager: SSE stream ended while streaming — '
        'scheduling reconnect');
    // The stream ended while we still want to be streaming → treat as a
    // retryable drop so the FSM schedules a reconnect.
    await _apply(const SocketError(retryable: true));
  }

  Future<void> close() async {
    // Defensively cancel any pending proactive token refresh: tearing down the
    // socket outside an FSM connection edge must not leave a refresh armed
    // against a dead connection (§11.3). A fresh one is rescheduled on the next
    // successful connect via the ScheduleTokenRefresh effect.
    _cancelTokenRefresh();
    final client = _client;
    _client = null;
    if (client != null) {
      await client.close();
    }
  }
}
