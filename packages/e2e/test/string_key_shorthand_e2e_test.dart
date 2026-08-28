import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

void main() {
  group('String key shorthand e2e', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test('create(sdkKey, config, "CUSTOMER_ID") wires through sync pipeline',
        () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      backend.stubAuth();
      backend.stubStreaming();

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      // String shorthand — no Key(...) wrapper.
      final factory =
          SplitFactory.create('fake-api-key', config, 'CUSTOMER_ID');

      // String shorthand on client() too.
      final client = factory.client('CUSTOMER_ID');

      await expectLater(
          client.whenReady().timeout(const Duration(seconds: 5)), completes);

      // /splitChanges MUST have fired at least once.
      expect(backend.splitChangesRequests, isNotEmpty,
          reason: '/splitChanges request must fire for String-key factory');

      // getTreatment on the shorthand client returns a real (non-thrown) value.
      // No flags are defined in the fixture, so control is expected — but the
      // point is that the call goes through the real evaluator, not the NoOp.
      expect(client.getTreatment('any_flag'), 'control');

      await factory.destroy();
    });

    test(
        'factory.client("X") returns same instance as factory.client(Key(matchingKey: "X"))',
        () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      backend.stubAuth();
      backend.stubStreaming();

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final factory =
          SplitFactory.create('fake-api-key', config, 'CUSTOMER_ID');

      final viaString = factory.client('SHARED_KEY');
      final viaKey = factory.client(const Key(matchingKey: 'SHARED_KEY'));

      expect(identical(viaString, viaKey), isTrue,
          reason:
              'Same cached SplitClient instance MUST be returned for equivalent keys (§8.5)');

      await factory.destroy();
    });

    test(
        'String-shorthand bootstrap key flows through as impression key '
        'with no bucketing key', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );

      final baseUrl = _baseUrl(backend);
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

      // String shorthand at the boundary — normalized to Key(matchingKey: 'user_a').
      final factory = SplitFactory.create('fake-api-key', config, 'user_a');

      await factory
          .client('user_a')
          .whenReady()
          .timeout(const Duration(seconds: 5));

      final client = factory.client('user_a');
      expect(client.getTreatment('test_flag_whitelist'), 'on');

      await factory.destroy();

      final posted = backend.postedImpressionsFlat;
      final match = posted.where(
        (imp) => imp['f'] == 'test_flag_whitelist' && imp['t'] == 'on',
      );
      expect(match, hasLength(1),
          reason: 'One impression MUST be posted for the evaluation');

      final actual = match.first;
      expect(actual['k'], equals('user_a'),
          reason:
              'Impression matching key MUST equal the String-shorthand bootstrap key');
      expect(actual['b'], isNull,
          reason:
              'Impression bucketing key MUST be null when boot key was a bare String');
    });
  });
}
