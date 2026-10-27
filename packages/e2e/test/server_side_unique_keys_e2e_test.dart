import 'dart:convert';

import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Server-side NONE-mode unique-keys (MTK) wire shape (spec §19.6, §19.1,
/// §13.2): server-side MUST post to `/v1/keys/ss` with
/// `{"keys":[{"f":"feature_name","ks":["key1","key2"]}]}` — grouped by
/// FEATURE, not by key. This differs from the client-side shape
/// (`/v1/keys/cs`, `{"keys":[{"k":"key","fs":["feature"]}]}`), which
/// `none_mode_recorder_test.dart` and `recorder_retry_e2e_test.dart` already
/// cover and which MUST remain unchanged.
Map<String, dynamic> _allKeysOnFlag(String name, {int changeNumber = 1000}) => {
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
      'sets': [],
    };

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

void main() {
  group('Server-side unique keys (MTK) wire shape (e2e, spec §19.6)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'NONE mode posts /v1/keys/ss with {f, ks} grouped by feature — '
        'not /v1/keys/cs', () async {
      backend.stubSplitChanges(splits: [
        _allKeysOnFlag('feature_a'),
        _allKeysOnFlag('feature_b'),
      ]);
      backend.stubUniqueKeysSs();

      final baseUrl = _baseUrl(backend);
      final config = ss.SplitClientConfig(
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
        impressionsMode: ss.ImpressionsMode.none,
        installSignalHandler: false,
        logLevel: ss.LogLevel.warning,
      );

      final factory = ss.SplitFactory.create('fake-api-key', config);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      client.getTreatment('key1', 'feature_a');
      client.getTreatment('key2', 'feature_a');
      client.getTreatment('key1', 'feature_b');

      await factory.destroy();

      expect(backend.uniqueKeysRequests, isEmpty,
          reason: 'server-side MUST NOT post to /v1/keys/cs');
      expect(backend.uniqueKeysSsRequests, isNotEmpty,
          reason: 'server-side NONE mode must post to /v1/keys/ss');

      final body =
          jsonDecode(utf8.decode(backend.uniqueKeysSsRequests.first.body))
              as Map<String, dynamic>;
      final keys = (body['keys'] as List).cast<Map<String, dynamic>>();

      final featureA = keys.firstWhere((e) => e['f'] == 'feature_a');
      expect((featureA['ks'] as List).cast<String>(),
          containsAll(['key1', 'key2']));

      final featureB = keys.firstWhere((e) => e['f'] == 'feature_b');
      expect((featureB['ks'] as List).cast<String>(), equals(['key1']));
    });
  });
}
