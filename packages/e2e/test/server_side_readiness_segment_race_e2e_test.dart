import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Server-side readiness MUST NOT fire before the segments a flag depends on
/// have actually been fetched (spec §8.2).
///
/// Regression scenario: the initial `/splitChanges` fails, so the first
/// `/segmentChanges` pass (run right after it in `initialSync()`) sees zero
/// registered segments and trivially "succeeds". A later `/splitChanges`
/// poll then succeeds and registers a brand-new segment referenced by an
/// IN_SEGMENT rule — but that segment's membership data has not been fetched
/// yet (that only happens on the *next* segments poll tick). If 'flags'
/// synced is latched as soon as the flags HTTP call succeeds, READY fires
/// one poll cycle too early and `getTreatment` evaluates the IN_SEGMENT rule
/// against an empty segment.
String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

/// A single flag whose rollout condition references the `beta_users`
/// segment via an IN_SEGMENT matcher.
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
      readyTimeout: 1,
      // Both clamped up to the 30s floor by SyncConfig.normalized() — this
      // test waits out real poll cycles rather than special-casing a faster
      // rate.
      featureFlagsPollingRate: 1,
      segmentsPollingRate: 1,
      // Streaming disabled so the organic poll fallback runs directly,
      // without depending on a separate, already-tracked bug where polling
      // never starts if streaming never connects.
      streamingEnabled: false,
    ),
    installSignalHandler: false,
    logLevel: LogLevel.warning,
  );
}

void main() {
  group('Server-side readiness vs. segment completeness (spec §8.2)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'READY does not fire until the segment a late-arriving flag '
        'depends on has itself been fetched', () async {
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

      // Every /segmentChanges/beta_users call returns the member — including
      // the very first one, which (before the flag has ever synced) runs
      // against zero registered segments and is a no-op for 'beta_users'.
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

      final factory = SplitFactory.create('fake-api-key', _config(backend));
      final client = factory.client();

      // Both poll timers are floored to a 30s period and started together,
      // so their first ticks race: the segments tick can run before that
      // same round's flags tick has registered `beta_users`, in which case
      // the fix correctly withholds READY until the *second* segments tick
      // (~60s in) rather than firing one segment-cycle early. The timeout
      // below accommodates that worst-case ordering without flaking.
      await expectLater(
          client.whenReady().timeout(const Duration(seconds: 75)), completes,
          reason: 'whenReady() MUST eventually complete once both the flag '
              'and the segment it depends on have synced');

      expect(
          client.getTreatment('member_key', 'flag_with_segment'), equals('on'),
          reason: 'Once READY fires, the segment data the flag depends on '
              'MUST already be loaded — not just the flag itself. If this '
              'returns the default treatment ("off"), READY fired before '
              '/segmentChanges/beta_users was actually fetched (spec §8.2).');

      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
