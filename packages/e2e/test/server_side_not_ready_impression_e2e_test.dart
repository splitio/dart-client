import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Server-side: evaluating before READY MUST return control AND record an
/// impression labeled `not ready` with no changeNumber (spec §8.2;
/// javascript-commons `sdkClient/client.ts`).

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

void main() {
  group('Server-side evaluation before READY (e2e, spec §8.2)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'getTreatment before READY returns control and posts an impression '
        'labeled "not ready" without "c"', () async {
      backend.stubSplitChangesHandler((_, __) => MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode({
            'ff': {
              's': -1,
              't': 1000,
              'd': [_allKeysOnFlag('feature_a')]
            },
            'rbs': {'s': -1, 't': 1000, 'd': []},
          }))
          .withDelay(const Duration(seconds: 3)));
      backend.stubImpressionsBulkHandler(
          (_, __) => MockResponse().setStatusCode(200));
      backend.stubEvents();

      final baseUrl = _baseUrl(backend);
      final factory = ss.SplitFactory.create(
          'fake-api-key',
          ss.SplitClientConfig(
            sync: ss.SyncConfig(
              serviceEndpoints: ss.ServiceEndpoints(
                sdkUrl: baseUrl,
                eventsUrl: baseUrl,
                telemetryUrl: baseUrl,
              ),
              featureFlagsPollingRate: 9999,
              segmentsPollingRate: 9999,
              streamingEnabled: false,
            ),
            impressionsMode: ss.ImpressionsMode.debug,
            installSignalHandler: false,
            logLevel: ss.LogLevel.warning,
          ));
      final client = factory.client();

      expect(client.getTreatment('key1', 'feature_a'), 'control');

      await factory.destroy();

      final imps = backend.postedImpressionsFlat;
      expect(imps, hasLength(1));
      expect(imps.single['f'], 'feature_a');
      expect(imps.single['k'], 'key1');
      expect(imps.single['t'], 'control');
      expect(imps.single['r'], 'not ready');
      expect(imps.single.containsKey('c'), isFalse);
    }, timeout: const Timeout(Duration(seconds: 20)));
    test(
        'ByFlagSets before READY (rules loaded, segments pending) return an '
        'empty map and post no impression', () async {
      final flag = _allKeysOnFlag('feature_a', sets: ['set_a']);
      final condition = (flag['conditions'] as List).single as Map;
      final matcher = ((condition['matcherGroup'] as Map)['matchers'] as List)
          .single as Map<String, dynamic>;
      matcher['matcherType'] = 'IN_SEGMENT';
      matcher['userDefinedSegmentMatcherData'] = {'segmentName': 'seg'};
      backend.stubSplitChanges(splits: [flag]);
      backend.stubSegmentChangesHandler((req, _) => MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode({
            'name': 'seg',
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': 1000,
          }))
          .withDelay(const Duration(seconds: 3)));
      backend.stubImpressionsBulkHandler(
          (_, __) => MockResponse().setStatusCode(200));
      backend.stubEvents();

      final baseUrl = _baseUrl(backend);
      final factory = ss.SplitFactory.create(
          'fake-api-key',
          ss.SplitClientConfig(
            sync: ss.SyncConfig(
              serviceEndpoints: ss.ServiceEndpoints(
                sdkUrl: baseUrl,
                eventsUrl: baseUrl,
                telemetryUrl: baseUrl,
              ),
              featureFlagsPollingRate: 9999,
              segmentsPollingRate: 9999,
              streamingEnabled: false,
            ),
            impressionsMode: ss.ImpressionsMode.debug,
            installSignalHandler: false,
            logLevel: ss.LogLevel.warning,
          ));
      final client = factory.client();

      // The segment fetch starts only after the flags are stored, so once it
      // is seen the rule store holds `feature_a` while READY is still pending.
      while (backend.segmentChangesRequests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(client.getTreatmentsByFlagSets('key1', ['set_a']), isEmpty);
      expect(
          client.getTreatmentsWithConfigByFlagSets('key1', ['set_a']), isEmpty);

      await factory.destroy();

      expect(backend.postedImpressionsFlat, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
