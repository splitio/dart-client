import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// End-to-end streaming tests exercised through the real SDK boundary using
/// [MockBackend]/MockWebServer. They assert the streaming happy path and the
/// two fallback paths described in the spec:
///   - §8.1  streaming starts AFTER the initial fetch
///   - §8.3  auth/channel coupling (GET /v2/auth)
///   - §8.4  push↔poll fallback
///   - §11   streaming state machine (SSE connection opens; disconnect →
///           reconnect → poll; token error → invalidate + reconnect)
///   - §12   notification strategies (SPLIT_UPDATE triggers an observable
///           re-sync)
///
/// Streaming is enabled by default (`SyncConfig.streamingEnabled == true`) and
/// targets `ServiceEndpoints.streamingUrl`, which these tests point at the mock
/// server so the SSE connection is observable.

/// Polls [condition] until it is true or [timeout] elapses. Used because
/// streaming start is fire-and-forget off the readiness critical path
/// (§8.1/§8.2), so the observable HTTP calls (auth, SSE, catch-up fetch) land
/// asynchronously after READY.
/// Returns `true` if [condition] became true before the deadline, `false` if
/// the timeout elapsed with the condition still unmet. Call sites MUST assert
/// on the returned value (`expect(await _until(...), isTrue, ...)`) so a
/// genuinely-unmet condition FAILS the test rather than silently passing on a
/// timeout/expect race.
Future<bool> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(interval);
  }
  return condition();
}

void main() {
  group('Streaming happy path', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'auth + SSE connection open after init fetch, SPLIT_UPDATE triggers '
        're-sync', () async {
      // Initial rules at change number 1000.
      backend.stubSplitChanges(since: 1000);
      // Memberships for any key (so readiness completes).
      backend.stubMemberships();
      backend.stubAuth();
      // Streaming pushes a SPLIT_UPDATE with a HIGHER change number than the
      // initial /splitChanges, which MUST trigger an observable re-sync.
      backend.stubStreaming(events: [
        MockBackend.splitUpdateEvent(changeNumber: 1001),
      ]);

      final baseUrl = _baseUrl(backend);

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      // Streaming starts AFTER the initial fetch and is fire-and-forget so it
      // MUST NOT delay readiness (§8.1/§8.2). Give the background auth + SSE
      // connect a moment to run before asserting on the observable HTTP calls.

      // 1. Auth request MUST fire (streaming JWT auth, §8.3 / §19.3).
      expect(await _until(() => backend.authRequests.isNotEmpty), isTrue,
          reason: 'GET /v2/auth MUST be requested to obtain a streaming JWT');

      // 2. SSE connection MUST open (§11 state machine).
      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');

      // 3. The SPLIT_UPDATE notification MUST produce an observable outcome:
      //    on fetch-fallback, a subsequent /splitChanges fetch. The initial
      //    fetch is the first request; the notification triggers at least one
      //    more.
      expect(
          await _until(() => backend.splitChangesRequests.length > 1), isTrue,
          reason:
              'SPLIT_UPDATE with a higher change number MUST trigger a re-sync '
              'observable as an additional /splitChanges fetch');

      // The re-sync MUST be the notification catch-up: the FlagsFetcher builds
      // its cursor from the STORED change number (`since = _ruleStore
      // .changeNumber()`), not the notification's changeNumber. The initial
      // fetch stored cn=1000 (the mock's `t`), so the catch-up fetch sends
      // `since=1000` to pull everything after the last stored CN.
      final secondFetch = backend.splitChangesRequests[1];
      expect(secondFetch.uri.queryParameters['since'], '1000',
          reason:
              'The re-sync MUST fetch from the last stored change number (1000) '
              'to catch up after the SPLIT_UPDATE notification');

      await factory.destroy();
    });

    test('SSE connection failure drives reconnect attempts (§11.3)', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      backend.stubAuth();
      // Simulate a connection that never establishes: every SSE connect returns
      // a transient 5xx (spec §10.3 → retryable). Two consecutive failures with
      // no successful open drop the connection axis (connectionDown) → the FSM
      // notifies push-disabled and SyncManager (re)starts polling (§8.4). The
      // FSM keeps scheduling backed-off reconnects, so the observable HTTP
      // signature of the fallback machinery is repeated SSE connect attempts
      // after the first drop.
      backend.stubStreamingStatus(500);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      // The SSE connection MUST be (re)attempted after the initial failure.
      // This verifies retry-on-transient-failure: the SDK MUST NOT give up
      // streaming after a single 5xx (backoff base is 1s, so >1 attempt lands
      // comfortably inside the window). Poll fallback (§8.4) is also triggered
      // internally when the connection axis drops, but the polling floor is
      // ~30s, so it is NOT HTTP-observable within this test window — repeated
      // SSE connect attempts are the honest observable here.
      expect(
          await _until(() => backend.streamingRequests.length > 1,
              timeout: const Duration(seconds: 8)),
          isTrue,
          reason:
              'A failed SSE connection MUST trigger reconnect attempts; the SDK '
              'MUST NOT give up streaming after a single transient failure');

      await factory.destroy();
    });

    test(
        'SSE 401 token error invalidates the token and re-auths on reconnect '
        '(§11.3)', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      // Auth succeeds and returns a valid push-enabled JWT every time.
      backend.stubAuth();
      // The SSE connect itself returns 401 → token error (spec §10.3/§11.3):
      // the FSM MUST invalidate the cached token and reconnect, which forces a
      // FRESH /v2/auth fetch (the token cache was cleared). Observable as a
      // second auth request.
      backend.stubStreamingStatus(401);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      // First auth fires, SSE connect gets 401, token invalidated, reconnect
      // pulls a fresh credential → a SECOND /v2/auth request.
      //
      // This is a black-box assertion: it verifies a FRESH /v2/auth occurred,
      // which implies the cached token was cleared (invalidate + reconnect per
      // §11.3). It cannot directly assert the internal FSM transition
      // (ErrorFrame(isTokenError: true) → InvalidateToken) — only its
      // HTTP-observable consequence.
      expect(
          await _until(() => backend.authRequests.length > 1,
              timeout: const Duration(seconds: 8)),
          isTrue,
          reason:
              'A 401 on the SSE connect MUST invalidate the streaming token and '
              're-auth on reconnect, producing an additional /v2/auth request');

      await factory.destroy();
    });

    test(
        'proactive token refresh re-auths and reconnects before expiry (§11.3)',
        () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      // A short-TTL token: `exp = now + 60 s`, so `expiresAt − refreshLeadTime`
      // (10 min) is already in the past → the runtime's proactive refresh timer
      // clamps to its minimum delay and fires promptly. Each refresh MUST
      // invalidate the token, tear down the socket and reconnect, pulling a
      // FRESH /v2/auth. The SSE connection is held OPEN so it never ends on its
      // own — the ONLY thing that can force a fresh auth + new connect is the
      // proactive refresh, isolating it from the reactive token-error path.
      backend.stubAuth(ttlSeconds: 60);
      backend.stubStreamingOpen();

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      // First auth + SSE connect happen on start.
      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');

      // The proactive refresh MUST re-auth (fresh /v2/auth) and reconnect
      // (a second SSE connect) before the token expires.
      expect(
          await _until(() => backend.authRequests.length > 1,
              timeout: const Duration(seconds: 8)),
          isTrue,
          reason:
              'The streaming runtime MUST proactively refresh the token before '
              'expiry, producing an additional /v2/auth request');
      expect(
          await _until(() => backend.streamingRequests.length > 1,
              timeout: const Duration(seconds: 8)),
          isTrue,
          reason:
              'The proactive refresh MUST reconnect the SSE connection with the '
              'fresh token');

      await factory.destroy();
    });
  });
}

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;
