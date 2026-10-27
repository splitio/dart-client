import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Keys MUST be percent-encoded as a single path segment in
/// `/memberships/{key}` (spec §13.2).
void main() {
  group('Memberships key URL encoding e2e', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
      backend.stubSplitChanges();
      backend.stubMemberships();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    for (final c in {
      'a/b c': '/memberships/a%2Fb%20c',
      'ñandú': '/memberships/%C3%B1and%C3%BA',
    }.entries) {
      test('client("${c.key}") requests ${c.value}', () async {
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
          logLevel: LogLevel.warning,
        );
        final factory = SplitFactory.create(
            'fake-api-key', config, Key(matchingKey: 'default_user'));
        final client = factory.client(Key(matchingKey: c.key));
        await client.whenReady().timeout(const Duration(seconds: 5));

        final paths =
            backend.membershipsRequests.map((r) => r.uri.path).toList();
        expect(paths, contains(c.value));
        await factory.destroy();
      });
    }
  });
}
