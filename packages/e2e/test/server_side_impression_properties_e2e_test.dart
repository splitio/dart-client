import 'dart:io';

import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Evaluation `properties` MUST reach the posted impression as a JSON-encoded
/// string (spec §13.2, A.5); OPTIMIZED MUST NOT dedupe impressions that carry
/// properties.
void main() {
  group('Server-side impression properties e2e', () {
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
        '${Directory.current.path}/test/shared_data/engine_features_suite',
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
        installSignalHandler: false,
        logLevel: LogLevel.warning,
      );
      final factory = SplitFactory.create('fake-api-key', config);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));
      body(client);
      await factory.destroy();
      return backend.postedImpressionsFlat
          .where((i) => i['f'] == 'flag_bucketing_key_split')
          .toList();
    }

    test('DEBUG posts properties as a JSON string', () async {
      final posted = await run(ImpressionsMode.debug, (c) {
        c.getTreatment('user_a', 'flag_bucketing_key_split',
            opts: const EvaluationOptions(properties: {'src': 'cs', 'n': 2}));
      });
      expect(posted, hasLength(1));
      expect(posted.first['properties'], '{"src":"cs","n":2}');
    });

    test('DEBUG omits properties when none are given', () async {
      final posted = await run(ImpressionsMode.debug, (c) {
        c.getTreatment('user_a', 'flag_bucketing_key_split');
      });
      expect(posted, hasLength(1));
      expect(posted.first.containsKey('properties'), isFalse);
    });

    test('OPTIMIZED posts both identical evaluations that carry properties',
        () async {
      final posted = await run(ImpressionsMode.optimized, (c) {
        for (var i = 0; i < 2; i++) {
          c.getTreatment('user_a', 'flag_bucketing_key_split',
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
