// Covers the BREAKING change (spec §7): multi-flag evaluation methods
// (getTreatments, getTreatmentsWithConfig, and their ByFlagSets variants)
// now return a Map keyed by flag name instead of a List, on both the
// client-side (SplitClient) and server-side (ServerSplitClient) flavors.
//
// Asserted via real HTTP interactions against a MockBackend (never against
// internal components), per the repo's e2e testing requirements.
import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

/// An always-"on" ALL_KEYS split, optionally carrying flag sets and a
/// per-treatment config, for exercising getTreatments*/ByFlagSets.
Map<String, dynamic> _alwaysOnFlag({
  required String name,
  List<String> sets = const [],
  Map<String, dynamic> configurations = const {},
}) {
  return {
    'trafficTypeName': 'user',
    'name': name,
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
          {'treatment': 'on', 'size': 100},
        ],
        'label': 'default rule',
      }
    ],
    'configurations': configurations,
    'sets': sets,
  };
}

/// Builds a /splitChanges 200 response carrying [flags], mirroring the
/// shape `MockBackend` itself returns from `stubSplitChanges`.
MockResponse _splitChangesWith(List<Map<String, dynamic>> flags) {
  return MockResponse()
      .setStatusCode(200)
      .setHeader('Content-Type', 'application/json')
      .setBody(jsonEncode({
        'ff': {'s': -1, 't': 1000, 'd': flags},
        'rbs': {'s': -1, 't': 1000, 'd': []},
      }));
}

List<Map<String, dynamic>> _flags() => [
      _alwaysOnFlag(
          name: 'flag_a', sets: ['set1'], configurations: {'on': '{"v":"a"}'}),
      _alwaysOnFlag(
          name: 'flag_b',
          sets: ['set1', 'set2'],
          configurations: {'on': '{"v":"b"}'}),
      _alwaysOnFlag(
          name: 'flag_c', sets: ['set2'], configurations: {'on': '{"v":"c"}'}),
    ];

void main() {
  group('Multi-flag evaluation methods return a Map keyed by flag name', () {
    group('client-side (SplitClient)', () {
      late MockBackend backend;
      late cs.SplitFactory factory;
      late cs.SplitClient client;

      setUp(() async {
        backend = MockBackend();
        await backend.start();
        backend.stubSplitChangesHandler((_, __) => _splitChangesWith(_flags()));
        backend.stubEvents();
        backend.stubMemberships();

        final config = cs.SplitClientConfig(
          sync: cs.SyncConfig(
            serviceEndpoints: cs.ServiceEndpoints(
                sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
            featureFlagsPollingRate: 9999,
            segmentsPollingRate: 9999,
            impressionsPushRate: 9999,
            eventsPushRate: 9999,
          ),
          logLevel: cs.LogLevel.error,
        );
        final key = cs.Key(matchingKey: 'user_a');
        factory = cs.SplitFactory.create('fake-api-key', config, key);
        client = factory.client(key);
        await client.whenReady().timeout(const Duration(seconds: 5));
      });

      tearDown(() async {
        await factory.destroy();
        await backend.shutdown();
      });

      test('getTreatments: empty input returns an empty map', () {
        expect(client.getTreatments(const []), isA<Map<String, String>>());
        expect(client.getTreatments(const []), isEmpty);
      });

      test(
          'getTreatments: trims whitespace, dedups, omits invalid names, '
          'keyed by validated flag name', () {
        final result =
            client.getTreatments(['  flag_a  ', 'flag_a', '', '   ', 'flag_b']);

        expect(result, isA<Map<String, String>>());
        expect(result, {'flag_a': 'on', 'flag_b': 'on'});
      });

      test('getTreatments: a flag missing from the ruleset maps to control',
          () {
        final result = client.getTreatments(['flag_a', 'nonexistent_flag']);

        expect(result, {'flag_a': 'on', 'nonexistent_flag': 'control'});
      });

      test(
          'getTreatmentsWithConfig: returns Map<String, EvaluationResult> '
          'keyed by flag name', () {
        final result = client.getTreatmentsWithConfig(['flag_a', 'flag_b']);

        expect(result, isA<Map<String, cs.EvaluationResult>>());
        expect(result.keys.toSet(), {'flag_a', 'flag_b'});
        expect(result['flag_a']!.treatment, 'on');
        expect(result['flag_a']!.config, '{"v":"a"}');
        expect(result['flag_b']!.treatment, 'on');
        expect(result['flag_b']!.config, '{"v":"b"}');
      });

      test(
          'getTreatmentsByFlagSets: keys are the flag names belonging to '
          'the requested sets', () {
        final result = client.getTreatmentsByFlagSets(['set1']);

        expect(result, isA<Map<String, String>>());
        expect(result, {'flag_a': 'on', 'flag_b': 'on'});
      });

      test('getTreatmentsByFlagSets: empty input returns an empty map', () {
        expect(client.getTreatmentsByFlagSets(const []), isEmpty);
      });

      test(
          'getTreatmentsWithConfigByFlagSets: keyed by flag name, with '
          'treatment + config', () {
        final result = client.getTreatmentsWithConfigByFlagSets(['set2']);

        expect(result, isA<Map<String, cs.EvaluationResult>>());
        expect(result.keys.toSet(), {'flag_b', 'flag_c'});
        expect(result['flag_b']!.config, '{"v":"b"}');
        expect(result['flag_c']!.config, '{"v":"c"}');
      });
    });

    group('server-side (ServerSplitClient)', () {
      late MockBackend backend;
      late ss.SplitFactory factory;
      late ss.ServerSplitClient client;
      const userKey = 'user_a';

      setUp(() async {
        backend = MockBackend();
        await backend.start();
        backend.stubSplitChangesHandler((_, __) => _splitChangesWith(_flags()));
        backend.stubEvents();
        backend.stubSegmentChanges();

        final config = ss.SplitClientConfig(
          sync: ss.SyncConfig(
            serviceEndpoints: ss.ServiceEndpoints(
                sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
            featureFlagsPollingRate: 9999,
            segmentsPollingRate: 9999,
            impressionsPushRate: 9999,
            eventsPushRate: 9999,
          ),
          installSignalHandler: false,
          logLevel: ss.LogLevel.error,
        );
        factory = ss.SplitFactory.create('fake-api-key', config);
        client = factory.client();
        await client.whenReady().timeout(const Duration(seconds: 5));
      });

      tearDown(() async {
        await factory.destroy();
        await backend.shutdown();
      });

      test('getTreatments: empty input returns an empty map', () {
        expect(client.getTreatments(userKey, const []), isEmpty);
      });

      test(
          'getTreatments: trims whitespace, dedups, omits invalid names, '
          'keyed by validated flag name, key passed first', () {
        final result = client.getTreatments(
            userKey, ['  flag_a  ', 'flag_a', '', '   ', 'flag_b']);

        expect(result, {'flag_a': 'on', 'flag_b': 'on'});
      });

      test('getTreatments: a flag missing from the ruleset maps to control',
          () {
        final result =
            client.getTreatments(userKey, ['flag_a', 'nonexistent_flag']);

        expect(result, {'flag_a': 'on', 'nonexistent_flag': 'control'});
      });

      test(
          'getTreatmentsWithConfig: returns Map<String, EvaluationResult> '
          'keyed by flag name', () {
        final result =
            client.getTreatmentsWithConfig(userKey, ['flag_a', 'flag_b']);

        expect(result.keys.toSet(), {'flag_a', 'flag_b'});
        expect(result['flag_a']!.treatment, 'on');
        expect(result['flag_a']!.config, '{"v":"a"}');
      });

      test(
          'getTreatmentsByFlagSets: keys are the flag names belonging to '
          'the requested sets', () {
        final result = client.getTreatmentsByFlagSets(userKey, ['set1']);

        expect(result, {'flag_a': 'on', 'flag_b': 'on'});
      });

      test(
          'getTreatmentsWithConfigByFlagSets: keyed by flag name, with '
          'treatment + config', () {
        final result =
            client.getTreatmentsWithConfigByFlagSets(userKey, ['set2']);

        expect(result.keys.toSet(), {'flag_b', 'flag_c'});
      });
    });
  });
}
