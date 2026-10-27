import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Evaluation `properties` MUST reach the posted impression as a JSON-encoded
/// string (spec §13.2, A.5); OPTIMIZED MUST NOT dedupe impressions that carry
/// properties.
void main() {
  group('Client-side impression properties e2e', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    Future<List<Map<String, dynamic>>> run(
      ImpressionsMode mode,
      void Function(dynamic client) body,
    ) async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints:
              ServiceEndpoints(sdkUrl: baseUrl, eventsUrl: baseUrl),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
        ),
        impressionsMode: mode,
        logLevel: LogLevel.warning,
      );
      final factory = SplitFactory.create(
          'fake-api-key', config, Key(matchingKey: 'user_a'));
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));
      body(client);
      await factory.destroy();
      return backend.postedImpressionsFlat
          .where((i) => i['f'] == 'test_flag_whitelist')
          .toList();
    }

    test('DEBUG posts properties as a JSON string', () async {
      final posted = await run(ImpressionsMode.debug, (c) {
        c.getTreatment('test_flag_whitelist',
            opts: const EvaluationOptions(properties: {'src': 'cs', 'n': 2}));
      });
      expect(posted, hasLength(1));
      expect(posted.first['properties'], '{"src":"cs","n":2}');
    });

    test('DEBUG omits properties when none are given', () async {
      final posted = await run(ImpressionsMode.debug, (c) {
        c.getTreatment('test_flag_whitelist');
      });
      expect(posted, hasLength(1));
      expect(posted.first.containsKey('properties'), isFalse);
    });

    test('OPTIMIZED posts both identical evaluations that carry properties',
        () async {
      final posted = await run(ImpressionsMode.optimized, (c) {
        for (var i = 0; i < 2; i++) {
          c.getTreatment('test_flag_whitelist',
              opts: const EvaluationOptions(properties: {'n': 2}));
        }
      });
      expect(posted, hasLength(2));
      for (final imp in posted) {
        expect(imp['properties'], '{"n":2}');
      }
    });
  });
}
