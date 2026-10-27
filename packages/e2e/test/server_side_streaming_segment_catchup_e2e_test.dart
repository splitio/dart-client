import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Server-side streaming segment catch-up (spec §11.3 Fetch effect, §17.2
/// Axis 3 server-side segment topology).
///
/// On server-side there is no per-key memberships fetcher; segment freshness
/// is normally driven by the polling `PollingManagerSS` segments timer. But
/// `SyncManager.onStreamingUp()` cancels that timer while push is up, so
/// a catch-up `Fetch` (emitted on reconnect/recovery) that only refreshes
/// rules — never segments — leaves every tracked segment stale until the
/// backend happens to send a SEGMENT_UPDATE for it.
///
/// This test drives push down (occupancy → 0) then push up again (occupancy →
/// non-zero) over a single SSE connection (spec §11.2's occupancy axis alone
/// flips the push gate; no socket teardown) and asserts an observable
/// `/segmentChanges/<name>` request lands after streaming's catch-up, not
/// just the `/splitChanges` one. The baseline is taken right after the
/// initial (pre-streaming) sync completes, so the only way the counts can
/// grow is via a streaming-driven catch-up fetch (`segmentsPollingRate` is
/// set far outside the test window, ruling out a poll-driven fetch).
String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

/// A single flag whose rollout condition references the `beta_users` segment
/// via an IN_SEGMENT matcher, so the server-side rule store registers that
/// segment name after the initial /splitChanges fetch (spec §17.2 Axis 3).
Map<String, dynamic> get _flagWithSegment => {
      'trafficTypeName': 'user',
      'name': 'flag_with_segment',
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 2,
      'status': 'ACTIVE',
      'killed': false,
      'defaultTreatment': 'off',
      'changeNumber': 1000,
      'algo': 2,
      'conditions': [
        {
          'conditionType': 'ROLLOUT',
          'matcherGroup': {
            'combiner': 'AND',
            'matchers': [
              {
                'keySelector': null,
                'matcherType': 'IN_SEGMENT',
                'negate': false,
                'userDefinedSegmentMatcherData': {
                  'segmentName': 'beta_users',
                },
                'whitelistMatcherData': null,
                'unaryNumericMatcherData': null,
                'betweenMatcherData': null,
                'booleanMatcherData': null,
                'dependencyMatcherData': null,
                'stringMatcherData': null,
              }
            ],
          },
          'partitions': [
            {'treatment': 'on', 'size': 100}
          ],
          'label': 'in segment beta_users',
        }
      ],
      'configurations': <String, dynamic>{},
      'sets': <String>[],
    };

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

void main() {
  group('Server-side streaming segment catch-up (§11.3)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'push down then push up triggers a /segmentChanges catch-up fetch, '
        'not just /splitChanges', () async {
      backend.stubSplitChanges(splits: [_flagWithSegment], since: 1000);
      backend.stubSegmentChanges();
      backend.stubAuth();
      // A single finite SSE connection carrying push-down then push-up
      // (occupancy 0, then non-zero). Spec §11.2: the occupancy axis alone
      // flips the push gate without a socket teardown, so this is one
      // connection, not a reconnect.
      backend.stubStreaming(events: [
        MockBackend.occupancyEvent(publishers: 0),
        MockBackend.occupancyEvent(publishers: 1),
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
          // Large enough that no incidental poll-driven fetch can fire within
          // the test window — any extra request MUST come from the streaming
          // catch-up path under test, not from polling.
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        installSignalHandler: false,
        logLevel: LogLevel.warning,
      );

      // Baseline taken right after the initial (pre-streaming) sync: one
      // /splitChanges and one /segmentChanges request from
      // `ServerDependencyContainer.initialSync()`, before streaming has even
      // connected. Any further request MUST come from a streaming-driven
      // catch-up fetch, not from polling (`segmentsPollingRate: 9999`).
      final factory = SplitFactory.create('fake-api-key', config);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      final splitChangesBaseline = backend.splitChangesRequests.length;
      final segmentChangesBaseline = backend.segmentChangesRequests.length;

      // Streaming connects and plays push-down (occupancy 0) then push-up
      // (occupancy 1) over the SAME connection — each push-up edge (the
      // initial connect AND the occupancy recovery) MUST emit a catch-up
      // `Fetch` (spec §11.3).
      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');

      expect(
          await _until(
              () => backend.splitChangesRequests.length > splitChangesBaseline),
          isTrue,
          reason: 'Streaming catch-up MUST trigger a /splitChanges fetch');

      expect(
          await _until(() =>
              backend.segmentChangesRequests.length > segmentChangesBaseline),
          isTrue,
          reason: 'Streaming catch-up MUST also refresh every tracked '
              'segment via /segmentChanges — not rules only. Segment stores '
              'otherwise stay stale until an unrelated SEGMENT_UPDATE frame '
              'arrives for each segment, since the poll timers that would '
              'normally refresh them are stopped while push is up.');

      await factory.destroy();
    });
  });
}
