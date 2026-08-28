import 'dart:convert';
import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

void main() {
  group('NONE mode recorders', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'flushes ImpressionsCount and UniqueKeys but NOT impressions bulk in NONE mode',
        () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            telemetryUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
        ),
        impressionsMode: ImpressionsMode.none,
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client(key);
      client.getTreatment('test_flag_whitelist');
      client.getTreatment('test_flag_whitelist');

      final key2 = Key(matchingKey: 'user_b');
      factory.client(key2).getTreatment('test_flag_whitelist');

      await factory.destroy();

      // Assert /testImpressions/bulk was NOT called
      final bulkRequests = backend.impressionRequests
          .where((r) => r.path.contains('bulk'))
          .toList();
      expect(bulkRequests, isEmpty,
          reason: 'NONE mode must not post to /testImpressions/bulk');

      // Assert /testImpressions/count WAS called with correct pf payload
      final countRequests = backend.impressionRequests
          .where((r) => r.path.contains('count'))
          .toList();
      expect(countRequests, isNotEmpty,
          reason: 'NONE mode must post to /testImpressions/count');

      final countBody = jsonDecode(utf8.decode(countRequests.first.body))
          as Map<String, dynamic>;
      final pf = countBody['pf'] as List;
      expect(pf, isNotEmpty);
      final pfEntry = pf
          .cast<Map<String, dynamic>>()
          .firstWhere((e) => e['f'] == 'test_flag_whitelist');
      expect(pfEntry['rc'], greaterThanOrEqualTo(1));
      expect(pfEntry['m'], isA<int>());

      // Assert /v1/keys/cs WAS called with correct keys payload
      expect(backend.uniqueKeysRequests, isNotEmpty,
          reason: 'NONE mode must post to /v1/keys/cs');

      final keysBody =
          jsonDecode(utf8.decode(backend.uniqueKeysRequests.first.body))
              as Map<String, dynamic>;
      final keys = (keysBody['keys'] as List).cast<Map<String, dynamic>>();
      expect(keys, isNotEmpty);

      final allMatchingKeys = keys.map((e) => e['k'] as String).toList();
      expect(allMatchingKeys, containsAll(['user_a', 'user_b']));
    });
  });
}
