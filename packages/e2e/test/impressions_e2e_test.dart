import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

void main() {
  group('Impressions flush on destroy', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test('posts queued impressions when factory is destroyed', () async {
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
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
        ),
        impressionsMode: ImpressionsMode.debug,
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client(key);
      final treatment = client.getTreatment('test_flag_whitelist');
      expect(treatment, 'on');

      expect(backend.impressionRequests, isEmpty,
          reason: 'No impressions posted yet (timer has not fired)');

      await factory.destroy();

      expect(backend.impressionRequests, isNotEmpty,
          reason: 'Impressions flushed on destroy');

      final posted = backend.postedImpressionsFlat;
      final match = posted.where(
        (imp) =>
            imp['f'] == 'test_flag_whitelist' &&
            imp['k'] == 'user_a' &&
            imp['t'] == 'on' &&
            imp['c'] == 1000 &&
            imp['r'] == 'whitelisted',
      );
      expect(match, hasLength(1));

      final actual = match.first;
      expect(actual['m'], isA<int>());
      expect((actual['m'] as int) > 0, isTrue);
    });

    test('does not post impressions for non-existent flags', () async {
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
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
        ),
        impressionsMode: ImpressionsMode.debug,
        logLevel: LogLevel.warning,
      );

      final key = Key(matchingKey: 'user_a');
      final factory = SplitFactory.create('fake-api-key', config, key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client(key);
      final treatment = client.getTreatment('non_existent_flag');
      expect(treatment, 'control');

      await factory.destroy();

      final posted = backend.postedImpressionsFlat;
      final match = posted.where(
        (imp) => imp['f'] == 'non_existent_flag',
      );
      expect(match, isEmpty, reason: 'No impression for non-existent flags');
    });
  });
}
