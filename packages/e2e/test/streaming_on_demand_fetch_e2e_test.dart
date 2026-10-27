import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Wraps [body] as a 200 JSON [MockResponse], mirroring the shape every
/// other handler in this suite (and `mock_backend.dart`) returns.
MockResponse _jsonResponse(Map<String, dynamic> body) => MockResponse()
    .setStatusCode(200)
    .setHeader('Content-Type', 'application/json')
    .setBody(jsonEncode(body));

/// End-to-end coverage for BUG #13 (spec §10.2): a `/splitChanges` or
/// `/segmentChanges` fetch triggered by a streaming notification can return a
/// stale CDN response (0 changes) even though the notified `changeNumber`
/// genuinely exists — a propagation-lag artifact. Before this fix, the SDK
/// never retried: it stayed on the stale definition forever, since polling is
/// stopped while push is up.
///
/// Both tests use a real, un-mocked backoff (base 10s per spec §19.5), so
/// they are inherently slow — kept to a single stale→fresh retry (not the
/// full 10-attempt + bypass sequence, which is covered by fast fake-time unit
/// tests instead) and given a generous [Timeout].
String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

/// Polls [condition] until it is true or [timeout] elapses. Call sites MUST
/// assert on the returned value so a genuinely-unmet condition FAILS the
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

Map<String, dynamic> _plainFlagDef({
  required String name,
  required int changeNumber,
  String defaultTreatment = 'off',
}) =>
    {
      'name': name,
      'trafficTypeName': 'user',
      'killed': false,
      'defaultTreatment': defaultTreatment,
      'conditions': <Map<String, dynamic>>[],
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 1,
      'algo': 2,
      'changeNumber': changeNumber,
      'status': 'ACTIVE',
      'configurations': <String, dynamic>{},
      'sets': <String>[],
    };

Map<String, dynamic> _splitChangesBody({
  required int ffSince,
  required int ffTill,
  List<Map<String, dynamic>> ffDiff = const [],
  int rbsSince = -1,
  int rbsTill = -1,
}) =>
    {
      'ff': {'s': ffSince, 't': ffTill, 'd': ffDiff},
      'rbs': {'s': rbsSince, 't': rbsTill, 'd': <Map<String, dynamic>>[]},
    };

void main() {
  group('Streaming on-demand fetch retry/bypass (spec §10.2, BUG #13)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'client-side: a stale /splitChanges response to a SPLIT_UPDATE '
        'notification is retried with Cache-Control: no-cache until it '
        'converges', () async {
      int coordinatorAttempt = 0;
      backend.stubSplitChangesHandler((req, callIndex) {
        final noCache = req.headers['cache-control'] == 'no-cache';
        Map<String, dynamic> body;
        if (callIndex == 0) {
          // Initial sync — no Cache-Control, baseline definition at cn=1000.
          body = _splitChangesBody(
            ffSince: -1,
            ffTill: 1000,
            ffDiff: [_plainFlagDef(name: 'flag_a', changeNumber: 1000)],
            rbsSince: -1,
            rbsTill: 1000,
          );
        } else if (!noCache) {
          // The catch-up fetch every push-up edge issues (spec §11.3),
          // independent of this bug — report no further changes.
          body = _splitChangesBody(
              ffSince: 1000, ffTill: 1000, rbsSince: 1000, rbsTill: 1000);
        } else {
          coordinatorAttempt++;
          if (coordinatorAttempt == 1) {
            // Stale CDN response: reports 0 changes even though cn=1001
            // genuinely exists (the bug this fix addresses).
            body = _splitChangesBody(
                ffSince: 1000, ffTill: 1000, rbsSince: 1000, rbsTill: 1000);
          } else {
            // Fresh: the retry converges.
            body = _splitChangesBody(
              ffSince: 1000,
              ffTill: 1001,
              ffDiff: [
                _plainFlagDef(
                    name: 'flag_a', changeNumber: 1001, defaultTreatment: 'on')
              ],
              rbsSince: 1000,
              rbsTill: 1000,
            );
          }
        }
        return _jsonResponse(body);
      });
      backend.stubMemberships();
      backend.stubAuth();
      backend.stubStreamingHold(events: [
        MockBackend.splitUpdateEvent(changeNumber: 1001),
      ]);

      final baseUrl = _baseUrl(backend);
      final config = cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: cs.LogLevel.warning,
      );

      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));

      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');

      final sseConnectedAt = DateTime.now();

      expect(
          await _until(() => updates.isNotEmpty,
              timeout: const Duration(seconds: 30)),
          isTrue,
          reason: 'The SDK MUST retry a stale on-demand fetch until it '
              'converges, instead of giving up after the first 0-change '
              'response');

      final elapsed = DateTime.now().difference(sseConnectedAt);
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 8)),
          reason: 'The retry MUST wait the spec §19.5 base backoff '
              '(10s) before re-fetching — a near-instant update means no '
              'retry/backoff actually happened');

      expect(updates.length, 1,
          reason: 'whenUpdated() MUST fire exactly once: the catch-up fetch '
              'and the stale retry are both no-op diffs, only the converged '
              'fetch carries a real change');
      expect(updates.first, contains('flag_a'));
      expect(client.getTreatment('flag_a'), 'on');

      final noCacheRequests = backend.splitChangesRequests
          .skip(1) // drop the initial sync request
          .where((r) => r.headers['cache-control'] == 'no-cache')
          .toList();
      final nonNoCacheRequests = backend.splitChangesRequests
          .skip(1)
          .where((r) => r.headers['cache-control'] != 'no-cache')
          .toList();
      expect(noCacheRequests.length, greaterThanOrEqualTo(2),
          reason: 'Every notification-triggered attempt (the stale one and '
              'the converging retry) MUST send Cache-Control: no-cache '
              '(spec §10.2)');
      // `stubStreamingHold` must close its first connection to actually flush
      // the queued SPLIT_UPDATE frame to the client — `dart:io` buffers a
      // chunked response body and only flushes on completion, so the mock
      // server can't otherwise deliver bytes over a connection that is held
      // open from the first byte (see mock_backend.dart's stubStreamingHold
      // doc). That close is read as a disconnect, so the SDK reconnects once
      // and runs one extra push-up catch-up fetch — a harness artifact, not
      // periodic polling (disabled here) or a second notification. Hence 2,
      // not 1, non-no-cache requests.
      expect(nonNoCacheRequests.length, 2,
          reason: 'Only the two push-up catch-up fetches (initial connect + '
              'the one harness-forced reconnect) should lack the header — '
              'periodic polls and the initial sync MUST NOT send it either, '
              'but polling is disabled in this test');

      await sub.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 45)));

    test(
        'server-side: a stale /segmentChanges response to a SEGMENT_UPDATE '
        'notification is retried with Cache-Control: no-cache until the '
        "segment's own cursor converges", () async {
      // flag_a references no segment, so the server-side catch-up aggregate
      // fetch (SegmentChangesFetcher.fetch(), which only loops registered
      // segments) never touches "seg_x" — every /segmentChanges/seg_x
      // request can only come from the SEGMENT_UPDATE-triggered coordinator.
      backend.stubSplitChanges(since: 1000, splits: [
        _plainFlagDef(name: 'flag_a', changeNumber: 1000),
      ]);
      int coordinatorAttempt = 0;
      backend.stubSegmentChangesHandler((req, callIndex) {
        final name = req.path.split('/').last;
        final noCache = req.headers['cache-control'] == 'no-cache';
        Map<String, dynamic> body;
        if (!noCache) {
          // Should not happen for an unregistered segment, but respond
          // caught-up defensively rather than lying about progress.
          body = {
            'name': name,
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          };
        } else {
          coordinatorAttempt++;
          if (coordinatorAttempt == 1) {
            // Stale CDN response: still reports -1 even though cn=5
            // genuinely exists.
            body = {
              'name': name,
              'added': <String>[],
              'removed': <String>[],
              'since': -1,
              'till': -1,
            };
          } else {
            body = {
              'name': name,
              'added': ['member_key'],
              'removed': <String>[],
              'since': -1,
              'till': 5,
            };
          }
        }
        return _jsonResponse(body);
      });
      backend.stubAuth();
      backend.stubStreamingHold(events: [
        MockBackend.segmentUpdateEvent(segmentName: 'seg_x', changeNumber: 5),
      ]);

      final baseUrl = _baseUrl(backend);
      final config = ss.SplitClientConfig(
        sync: ss.SyncConfig(
          serviceEndpoints: ss.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        installSignalHandler: false,
        logLevel: ss.LogLevel.warning,
      );

      final factory = ss.SplitFactory.create('fake-api-key', config);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');

      final sseConnectedAt = DateTime.now();

      // Scoped to `Cache-Control: no-cache` — the coordinator's own chase.
      // `stubStreamingHold` must close its first connection to actually
      // flush the queued SEGMENT_UPDATE frame — `dart:io` buffers a chunked
      // response body and only flushes on completion, so the mock server
      // can't otherwise deliver bytes over a connection held open from the
      // first byte (see mock_backend.dart's stubStreamingHold doc). That
      // close is read as a disconnect, so the SDK reconnects once; by then
      // "seg_x" is a registered segment (the coordinator's first fetch
      // registered it), so the harness-forced reconnect's own catch-up/poll
      // cycle also fetches it once — a plain, no-cache-less request that
      // must not be confused with the coordinator's chase.
      List<RecordedRequest> noCacheSegXRequests() =>
          backend.segmentChangesRequests
              .where((r) =>
                  r.path.endsWith('seg_x') &&
                  r.headers['cache-control'] == 'no-cache')
              .toList();

      expect(
          await _until(() => noCacheSegXRequests().length >= 2,
              timeout: const Duration(seconds: 30)),
          isTrue,
          reason: 'The SDK MUST retry a stale /segmentChanges response for '
              'the notified segment until the cursor converges');

      final elapsed = DateTime.now().difference(sseConnectedAt);
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 8)),
          reason: 'The retry MUST wait the spec §19.5 base backoff (10s) '
              'before re-fetching');

      expect(
          noCacheSegXRequests()
              .every((r) => r.headers['cache-control'] == 'no-cache'),
          isTrue,
          reason: 'Every SEGMENT_UPDATE-triggered attempt MUST send '
              'Cache-Control: no-cache (spec §10.2)');

      // Give the coordinator a window in which a (buggy) perpetual retry
      // would show up as additional requests past convergence.
      await Future<void>.delayed(const Duration(seconds: 3));
      // 3, not 2: `SegmentChangesFetcher.fetchForSegment` loops on its own
      // `since`/`till` cursor until a response reports no further change
      // (`till == since`), independent of the coordinator's retry/backoff —
      // the same greedy-pagination contract `fetch()`'s polling path relies
      // on. The stale attempt (#1) satisfies that in one call. The fresh
      // attempt (#2) reports an actual diff (`till=5 > since=-1`), so the
      // loop issues one more no-cache call with `since=5` to confirm nothing
      // further is pending before returning — that confirmation call is the
      // 3rd request. A count stuck growing past 3 would mean the coordinator
      // never detected the cursor catching up.
      expect(noCacheSegXRequests().length, 3,
          reason: 'Once converged, the coordinator MUST stop retrying — a '
              'count still growing after convergence means it never '
              'detected the cursor catching up');

      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
