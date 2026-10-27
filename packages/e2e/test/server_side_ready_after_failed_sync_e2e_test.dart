import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Regression test for a QA-reported bug (Node parity gap): when the
/// initial `/splitChanges` fails and the backend then recovers, READY
/// fires far later than it should.
///
/// Root cause: `PollingManagerSS.start` starts the flags and
/// segments `Timer.periodic` at the very same instant (right after the
/// failed initial sync). A later successful flags poll can register a
/// brand-new segment (via an IN_SEGMENT rule) that the segments timer has
/// no idea about yet — and, because that timer runs on its OWN,
/// independently-scheduled interval, the segment doesn't actually get
/// fetched until that timer's next tick. READY — gated on
/// `segmentStore.allRegisteredSegmentsFetched()` — is withheld for the
/// entire gap in between.
///
/// Node (`javascript-commons`) does not have this gap: any successful
/// flags fetch that registers a new segment name fetches it immediately.
/// This test pins that behavior: with the segments interval set far longer
/// than the flags interval, READY MUST still fire shortly after the first
/// successful flags poll — not after waiting out the segments interval.
String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

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

SplitClientConfig _config(MockBackend backend) {
  final baseUrl = _baseUrl(backend);
  return SplitClientConfig(
    sync: SyncConfig(
      serviceEndpoints: ServiceEndpoints(
        sdkUrl: baseUrl,
        eventsUrl: baseUrl,
        authUrl: baseUrl,
        streamingUrl: baseUrl,
      ),
      readyTimeout: 0,
      // Floored to 30s by SyncConfig.normalized() — the minimum allowed
      // features polling rate.
      featureFlagsPollingRate: 1,
      // Deliberately far longer than the flags interval: if READY has to
      // wait for THIS timer, it arrives minutes late. The fix must make
      // READY independent of this value entirely for this scenario.
      segmentsPollingRate: 300,
      streamingEnabled: false,
    ),
    installSignalHandler: false,
    logLevel: LogLevel.warning,
  );
}

void main() {
  group('Server-side READY after a failed-then-recovered initial sync', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'READY fires shortly after the first successful flags poll — well '
        'before the (much longer) segments polling interval — and the '
        'newly-referenced segment is fetched immediately', () async {
      backend.stubSplitChangesHandler((_, callIndex) {
        if (callIndex == 0) {
          return MockResponse().setStatusCode(500).setBody('internal error');
        }
        final body = jsonEncode({
          'ff': {
            's': -1,
            't': 1000,
            'd': [_flagWithSegment],
          },
          'rbs': {'s': -1, 't': 1000, 'd': []},
        });
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(body);
      });

      backend.stubSegmentChangesHandler((req, callIndex) {
        final name = req.path.split('/').last;
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(jsonEncode({
              'name': name,
              'added': ['member_key'],
              'removed': <String>[],
              'since': -1,
              'till': 2000,
            }));
      });

      final started = DateTime.now();
      final factory = SplitFactory.create('fake-api-key', _config(backend));
      final client = factory.client();

      // The flags interval is floored to 30s; the initial sync's failure
      // means the first successful flags fetch happens on that timer's
      // first tick (~30s in). Give generous scheduling slack but assert
      // well under the 300s segments interval below.
      await expectLater(
          client.whenReady().timeout(const Duration(seconds: 60)), completes,
          reason: 'whenReady() MUST complete once the recovered flags poll '
              'and the segment it depends on have synced — not stay '
              'pending until the next segments-timer tick (which, at a '
              '300s interval, this test would never observe within '
              'timeout).');
      final elapsed = DateTime.now().difference(started);

      expect(elapsed, lessThan(const Duration(seconds: 60)),
          reason: 'READY took as long as (or longer than) the segments '
              'polling interval — it waited for the segments timer instead '
              'of fetching the newly-registered segment immediately after '
              'the successful flags poll.');

      expect(
          client.getTreatment('member_key', 'flag_with_segment'), equals('on'),
          reason: 'Once READY fires, the segment data the flag depends on '
              'MUST already be loaded.');

      expect(backend.segmentChangesRequests, isNotEmpty,
          reason: '/segmentChanges/beta_users MUST have been requested '
              'immediately after the second (successful) /splitChanges '
              'fetch registered it — not deferred to the segments timer.');

      // Exactly two /splitChanges calls (initial failure + first recovered
      // poll) by the time READY fired — proves READY did not need a
      // SECOND flags poll (which would mean the fix wasn't actually
      // closing the gap, just happening to land before some later event).
      expect(backend.splitChangesRequests.length, equals(2));

      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 75)));
  });
}
