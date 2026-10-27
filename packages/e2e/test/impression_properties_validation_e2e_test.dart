// EvaluationOptions.properties MUST be validated at evaluation time like
// track properties (spec §4.1, §16): a non-JSON value (e.g. DateTime) is
// nulled, and MUST NOT make the impressions batch fail to encode and be
// dropped along with the other impressions.
import 'dart:convert';
import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

void _expectNulledProperties(List<Map<String, dynamic>> posted) {
  expect(posted, hasLength(2),
      reason: 'a non-JSON property value MUST NOT drop the impressions batch');
  expect(jsonDecode(posted.first['properties'] as String),
      {'when': null, 'ok': 'yes'});
  expect(posted.last.containsKey('properties'), isFalse);
}

void main() {
  late MockBackend backend;

  setUp(() async {
    backend = MockBackend();
    await backend.start();
  });

  tearDown(() async {
    await backend.shutdown();
  });

  test('client-side: DateTime property is nulled and the batch is posted',
      () async {
    backend.stubFromFixtures(
      '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
    );
    final base = _baseUrl(backend);
    final factory = cs.SplitFactory.create(
      'fake-api-key',
      cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(sdkUrl: base, eventsUrl: base),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
        ),
        impressionsMode: cs.ImpressionsMode.debug,
        logLevel: cs.LogLevel.error,
      ),
      cs.Key(matchingKey: 'user_a'),
    );
    final client = factory.client();
    await client.whenReady().timeout(const Duration(seconds: 5));
    client.getTreatment('test_flag_whitelist',
        opts: cs.EvaluationOptions(
            properties: {'when': DateTime(2020), 'ok': 'yes'}));
    client.getTreatment('test_flag_whitelist');
    await factory.destroy();

    _expectNulledProperties(backend.postedImpressionsFlat
        .where((i) => i['f'] == 'test_flag_whitelist')
        .toList());
  });

  test('server-side: DateTime property is nulled and the batch is posted',
      () async {
    backend.stubFromFixtures(
      '${Directory.current.path}/test/shared_data/engine_features_suite',
    );
    final base = _baseUrl(backend);
    final factory = ss.SplitFactory.create(
      'fake-api-key',
      ss.SplitClientConfig(
        sync: ss.SyncConfig(
          serviceEndpoints: ss.ServiceEndpoints(sdkUrl: base, eventsUrl: base),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
        ),
        impressionsMode: ss.ImpressionsMode.debug,
        installSignalHandler: false,
        logLevel: ss.LogLevel.error,
      ),
    );
    final client = factory.client();
    await client.whenReady().timeout(const Duration(seconds: 5));
    client.getTreatment('user_a', 'flag_bucketing_key_split',
        opts: ss.EvaluationOptions(
            properties: {'when': DateTime(2020), 'ok': 'yes'}));
    client.getTreatment('user_a', 'flag_bucketing_key_split');
    await factory.destroy();

    _expectNulledProperties(backend.postedImpressionsFlat
        .where((i) => i['f'] == 'flag_bucketing_key_split')
        .toList());
  });
}
