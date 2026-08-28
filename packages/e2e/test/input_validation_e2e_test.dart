import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

void main() {
  group('Input validation e2e', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    SplitClientConfig _config(String baseUrl) => SplitClientConfig(
          sync: SyncConfig(
            serviceEndpoints:
                ServiceEndpoints(sdkUrl: baseUrl, eventsUrl: baseUrl),
            featureFlagsPollingRate: 9999,
            segmentsPollingRate: 9999,
            impressionsPushRate: 9999,
            eventsPushRate: 9999,
          ),
          logLevel: LogLevel.error,
        );

    Future<SplitFactory> _buildFactory(Key key) async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;
      return SplitFactory.create('fake-api-key', _config(baseUrl), key);
    }

    test('invalid eventType is not sent to /events/bulk', () async {
      final key = Key(matchingKey: 'user_a');
      final factory = await _buildFactory(key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      // 'bad event' contains a space — invalid per spec §16
      final ok = factory.client(key).track('bad event', 'user');
      expect(ok, isFalse);

      await factory.destroy();
      expect(backend.postedEvents, isEmpty);
    });

    test('empty flag name returns control without hitting evaluator', () async {
      final key = Key(matchingKey: 'user_a');
      final factory = await _buildFactory(key);

      await factory
          .client(key)
          .whenReady()
          .timeout(const Duration(seconds: 5));

      expect(factory.client(key).getTreatment(''), 'control');
      expect(factory.client(key).getTreatment('   '), 'control');

      await factory.destroy();
    });

    test('over-length key returns NoOp factory (no /splitChanges call)',
        () async {
      final startCount = backend.splitChangesRequests.length;

      final factory = SplitFactory.create(
        'fake-api-key',
        _config(backend.url),
        Key(matchingKey: 'a' * 1025),
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
          factory.client(Key(matchingKey: 'a')).getTreatment('x'), 'control');
      expect(backend.splitChangesRequests.length, startCount);

      await factory.destroy();
    });
  });
}
