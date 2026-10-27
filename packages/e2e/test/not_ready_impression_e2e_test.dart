import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Client-side: evaluating on a client that is not yet READY MUST return
/// control AND record an impression labeled `not ready` with no changeNumber
/// (spec §8.2; javascript-commons `sdkClient/client.ts`).

Map<String, dynamic> _allKeysOnFlag(String name,
        {int changeNumber = 1000, List<String> sets = const []}) =>
    {
      'trafficTypeName': 'user',
      'name': name,
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 1,
      'status': 'ACTIVE',
      'killed': false,
      'defaultTreatment': 'off',
      'changeNumber': changeNumber,
      'algo': 2,
      'conditions': [
        {
          'conditionType': 'ROLLOUT',
          'matcherGroup': {
            'combiner': 'AND',
            'matchers': [
              {
                'keySelector': null,
                'matcherType': 'ALL_KEYS',
                'negate': false,
                'userDefinedSegmentMatcherData': null,
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
          'label': 'default rule',
        }
      ],
      'configurations': {},
      'sets': sets,
    };

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

SplitClientConfig _config(String baseUrl, ImpressionsMode mode) =>
    SplitClientConfig(
      sync: SyncConfig(
        serviceEndpoints: ServiceEndpoints(
          sdkUrl: baseUrl,
          eventsUrl: baseUrl,
          telemetryUrl: baseUrl,
          authUrl: baseUrl,
          streamingUrl: baseUrl,
        ),
        featureFlagsPollingRate: 9999,
        segmentsPollingRate: 9999,
        streamingEnabled: false,
      ),
      impressionsMode: mode,
      logLevel: LogLevel.warning,
    );

MockResponse _memberships() => MockResponse()
    .setStatusCode(200)
    .setHeader('Content-Type', 'application/json')
    .setBody(jsonEncode({
      'ms': {'k': <String>[], 'cn': 1000},
      'ls': {'k': <String>[], 'cn': -1},
    }));

void main() {
  group('Client-side evaluation before READY (e2e, spec §8.2)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
      backend.stubSplitChanges(splits: [
        _allKeysOnFlag('feature_a', sets: ['set_a'])
      ]);
      backend.stubMembershipsHandler((req, _) => req.path.endsWith('/slow_user')
          ? _memberships().withDelay(const Duration(seconds: 3))
          : _memberships());
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'DEBUG: getTreatment on a not-ready shared client returns control and '
        'posts an impression labeled "not ready" without "c"', () async {
      backend.stubImpressionsBulkHandler(
          (_, __) => MockResponse().setStatusCode(200));
      final factory = SplitFactory.create(
          'fake-api-key',
          _config(_baseUrl(backend), ImpressionsMode.debug),
          const Key(matchingKey: 'main_user'));
      await factory.client().whenReady().timeout(const Duration(seconds: 5));

      final slow = factory.client('slow_user');
      expect(slow.getTreatment('feature_a'), 'control');

      await factory.destroy();

      final imps = backend.postedImpressionsFlat
          .where((i) => i['k'] == 'slow_user')
          .toList();
      expect(imps, hasLength(1));
      expect(imps.single['f'], 'feature_a');
      expect(imps.single['t'], 'control');
      expect(imps.single['r'], 'not ready');
      expect(imps.single.containsKey('c'), isFalse);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('NONE: a not-ready evaluation registers the key on /v1/keys/cs',
        () async {
      backend
          .stubUniqueKeysHandler((_, __) => MockResponse().setStatusCode(200));
      backend.stubImpressionsCountHandler(
          (_, __) => MockResponse().setStatusCode(200));
      final factory = SplitFactory.create(
          'fake-api-key',
          _config(_baseUrl(backend), ImpressionsMode.none),
          const Key(matchingKey: 'main_user'));
      await factory.client().whenReady().timeout(const Duration(seconds: 5));

      final slow = factory.client('slow_user');
      expect(slow.getTreatment('feature_a'), 'control');

      await factory.destroy();

      final keys = backend.uniqueKeysRequests
          .expand((r) => ((jsonDecode(utf8.decode(r.body))
                  as Map<String, dynamic>)['keys'] as List)
              .cast<Map<String, dynamic>>())
          .toList();
      final entry = keys.where((e) => e['k'] == 'slow_user').toList();
      expect(entry, hasLength(1));
      expect((entry.single['fs'] as List).cast<String>(), ['feature_a']);
    }, timeout: const Timeout(Duration(seconds: 20)));
    test(
        'ByFlagSets on a not-ready shared client return an empty map and post '
        'no impression', () async {
      backend.stubImpressionsBulkHandler(
          (_, __) => MockResponse().setStatusCode(200));
      final factory = SplitFactory.create(
          'fake-api-key',
          _config(_baseUrl(backend), ImpressionsMode.debug),
          const Key(matchingKey: 'main_user'));
      await factory.client().whenReady().timeout(const Duration(seconds: 5));

      final slow = factory.client('slow_user');
      expect(slow.getTreatmentsByFlagSets(['set_a']), isEmpty);
      expect(slow.getTreatmentsWithConfigByFlagSets(['set_a']), isEmpty);

      await factory.destroy();

      expect(backend.postedImpressionsFlat.where((i) => i['k'] == 'slow_user'),
          isEmpty);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
