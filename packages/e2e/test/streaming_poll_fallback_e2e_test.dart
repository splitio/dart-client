import 'package:mock_http_server/mock_http_server.dart' show SseEvent;
import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Streaming → poll-fallback end-to-end tests (spec §11.3): every retryable
/// streaming failure MUST close the socket, drop the connection axis, notify
/// push-disabled (poll fallback) and schedule the next backoff step — on
/// EVERY such failure, including the very first one before any successful
/// connect. The old implementation only flipped the connection axis (and so
/// only ever notified poll-fallback) after >=2 consecutive failures, and
/// relied on a push-gate EDGE that never fires when the connection starts
/// (and stays) down — so a stream that never comes up left the SDK polling
/// nothing beyond the initial fetch.
///
/// These tests assert the HTTP-observable consequence: `/splitChanges`
/// polling actually runs while streaming is failing.
void main() {
  group('Streaming failure drives poll fallback (§11.3)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'SSE connects then the stream ends: polling resumes at the poll rate '
        'while streaming keeps failing', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      backend.stubAuth();
      // The SSE connection opens (200) but the event stream ends immediately
      // (no events) — SocketOpened then a retryable SocketError. This is a
      // single retryable failure AFTER a successful connect; the connection
      // axis drops on this very first failure (the old ">=2 consecutive
      // failures" rule is gone), so poll fallback MUST kick in right away.
      backend.stubStreaming(events: const []);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          // Polling floor is 30s (SplitClientConfig clamps below that); this
          // is the minimum period observable within a reasonable test window.
          featureFlagsPollingRate: 30,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);
      addTearDown(factory.destroy);

      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));

      // Baseline: 1 initial fetch + 1 streaming catch-up fetch (on
      // SocketOpened) land quickly, well before any poll timer could fire.
      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');
      expect(
          await _until(() => backend.splitChangesRequests.length >= 2), isTrue,
          reason: 'SocketOpened MUST trigger a catch-up /splitChanges fetch');
      final baseline = backend.splitChangesRequests.length;

      // Once the stream ends, the connection axis drops and poll fallback
      // MUST start: a THIRD /splitChanges request (beyond the initial fetch
      // and the streaming catch-up) MUST land once the poll timer fires.
      expect(
          await _until(() => backend.splitChangesRequests.length > baseline,
              timeout: const Duration(seconds: 50)),
          isTrue,
          reason: 'Polling MUST (re)start once the streaming connection '
              'drops, producing an additional /splitChanges request beyond '
              'the initial fetch and the streaming catch-up');
    }, timeout: const Timeout(Duration(seconds: 70)));

    test(
        'SSE never connects (repeated 5xx): polling runs even though '
        'streaming has NEVER come up', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      backend.stubAuth();
      // Every SSE connect attempt gets a transient 5xx (retryable, §10.3) —
      // the connection NEVER opens even once. This is the critical regression
      // case: `connectionDown` starts `true` and `pushUp` starts `false`, so
      // there is never an EDGE on the push gate to drive poll fallback. The
      // fix MUST notify push-disabled unconditionally on every retryable
      // failure, not just on an edge.
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
          featureFlagsPollingRate: 30,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);
      addTearDown(factory.destroy);

      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));

      // Only the initial fetch has landed so far — streaming has not (and
      // will not) succeed, so no catch-up fetch is expected.
      final baseline = backend.splitChangesRequests.length;
      expect(baseline, 1,
          reason: 'Only the initial /splitChanges fetch should have landed '
              'before streaming ever succeeds');

      expect(
          await _until(() => backend.splitChangesRequests.length > baseline,
              timeout: const Duration(seconds: 50)),
          isTrue,
          reason: 'Polling MUST run even though streaming has never '
              'successfully connected — the first retryable failure MUST '
              'notify push-disabled unconditionally');

      // Reconnect attempts MUST also keep happening (never give up).
      expect(
          await _until(() => backend.streamingRequests.length > 1,
              timeout: const Duration(seconds: 10)),
          isTrue,
          reason: 'The SDK MUST keep retrying the SSE connection, not give '
              'up after the first failure');
    }, timeout: const Timeout(Duration(seconds: 70)));

    test(
        'SSE connects then sends a 40144 token error: polling resumes and '
        'the SDK re-authenticates', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      backend.stubAuth();
      // The stage scenario: the SSE connection opens (200) and Ably then
      // sends a token error frame (40144). This is a retryable failure
      // (§11.3): poll fallback MUST engage and a fresh /auth MUST follow.
      backend.stubStreaming(events: const [
        SseEvent(
          event: 'error',
          data: '{"message":"Token expired","code":40144,"statusCode":401}',
        ),
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
          featureFlagsPollingRate: 30,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);
      addTearDown(factory.destroy);

      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');
      expect(
          await _until(() => backend.splitChangesRequests.length >= 2), isTrue,
          reason: 'SocketOpened MUST trigger a catch-up /splitChanges fetch');
      final baseline = backend.splitChangesRequests.length;

      expect(
          await _until(() => backend.authRequests.length > 1,
              timeout: const Duration(seconds: 10)),
          isTrue,
          reason: 'A token error MUST invalidate the token and re-auth');
      expect(
          await _until(() => backend.splitChangesRequests.length > baseline,
              timeout: const Duration(seconds: 50)),
          isTrue,
          reason: 'Polling MUST resume after a 40144 token error frame');
    }, timeout: const Timeout(Duration(seconds: 70)));
  });
}

/// Polls [condition] until it is true or [timeout] elapses. Returns `true` if
/// [condition] became true before the deadline, `false` otherwise. Call sites
/// MUST assert on the returned value so a genuinely-unmet condition FAILS the
/// test rather than silently passing on a timeout/expect race.
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

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;
