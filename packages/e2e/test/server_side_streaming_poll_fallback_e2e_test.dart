import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Server-side streaming → poll-fallback end-to-end test (spec §11.3).
///
/// Mirrors `streaming_poll_fallback_e2e_test.dart`'s "SSE never connects"
/// case for the server-side flavor: `SyncManager.startStreaming` only
/// starts polling on a `NotifyPushDisabled` EDGE in the old implementation,
/// but the connection axis starts (and, if streaming never comes up, stays)
/// down — so no edge ever fires and polling never starts. The fix MUST
/// notify push-disabled unconditionally on every retryable failure.
void main() {
  group('Server-side streaming failure drives poll fallback (§11.3)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'SSE never connects (repeated 5xx): polling runs even though '
        'streaming has NEVER come up', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubSegmentChanges();
      backend.stubAuth();
      // Every SSE connect attempt gets a transient 5xx (retryable, §10.3):
      // the connection NEVER opens even once.
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
          // Polling floor is 30s (SplitClientConfig clamps below that).
          featureFlagsPollingRate: 30,
          segmentsPollingRate: 9999,
        ),
        installSignalHandler: false,
        logLevel: LogLevel.warning,
      );

      final factory = SplitFactory.create('fake-api-key', config);
      addTearDown(factory.destroy);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      // Only the initial fetch (from ServerDependencyContainer.initialSync())
      // has landed so far — streaming has not (and will not) succeed.
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

      expect(
          await _until(() => backend.streamingRequests.length > 1,
              timeout: const Duration(seconds: 10)),
          isTrue,
          reason: 'The SDK MUST keep retrying the SSE connection, not give '
              'up after the first failure');
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
