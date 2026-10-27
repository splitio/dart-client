// An invalid (empty) feature flag name inside a getTreatments list MUST be
// logged at ERROR level (JS `validateDefinition` parity, spec §16), the
// remaining valid names still evaluate.
import 'dart:async';

import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

void main() {
  late MockBackend backend;

  setUp(() async {
    backend = MockBackend();
    await backend.start();
    backend.stubSplitChanges();
    backend.stubEvents();
  });

  tearDown(() async {
    await backend.shutdown();
  });

  test('empty name in getTreatments list logs ERROR, valid names evaluated',
      () async {
    final lines = <String>[];
    await runZoned(
      () async {
        final factory = SplitFactory.create(
          'fake-api-key',
          SplitClientConfig(
            sync: SyncConfig(
              serviceEndpoints: ServiceEndpoints(
                  sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
              featureFlagsPollingRate: 9999,
              segmentsPollingRate: 9999,
              impressionsPushRate: 9999,
              eventsPushRate: 9999,
              streamingEnabled: false,
            ),
            installSignalHandler: false,
            logLevel: LogLevel.warning,
          ),
        );
        final client = factory.client();
        await client.whenReady().timeout(const Duration(seconds: 5));
        final result = client.getTreatments('user-1', ['flag_a', '']);
        expect(result.keys, ['flag_a']);
        await factory.destroy();
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );
    expect(
        lines.where((l) =>
            l.contains('[ERROR]') && l.contains('empty feature flag name')),
        hasLength(1));
    expect(
        lines.where(
            (l) => l.contains('[WARNING]') && l.contains('empty feature flag')),
        isEmpty);
  });
}
