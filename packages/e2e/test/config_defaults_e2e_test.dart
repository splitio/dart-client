// Config defaults (spec §14, §19.4): the SDK is silent by default
// (`logLevel: LogLevel.none`) on both flavors, and the server-side flavor
// warns — naming the setting — when it clamps a polling/push rate below the
// 30 s minimum. Asserted via captured log output while the SDK talks to a
// MockBackend.
import 'dart:async';

import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

Future<List<String>> _captureLog(FutureOr<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    () async => await body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

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

  test('server-side default logLevel is silent', () async {
    final lines = await _captureLog(() async {
      final factory = ss.SplitFactory.create(
        'fake-api-key',
        ss.SplitClientConfig(
          sync: ss.SyncConfig(
            serviceEndpoints: ss.ServiceEndpoints(
                sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
            streamingEnabled: false,
          ),
          installSignalHandler: false,
        ),
      );
      await factory.client().whenReady().timeout(const Duration(seconds: 5));
      await factory.destroy();
    });
    expect(lines, isEmpty);
  });

  test('client-side default logLevel is silent', () async {
    final lines = await _captureLog(() async {
      final factory = cs.SplitFactory.create(
        'fake-api-key',
        cs.SplitClientConfig(
          sync: cs.SyncConfig(
            serviceEndpoints: cs.ServiceEndpoints(
                sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
            streamingEnabled: false,
          ),
        ),
        'user-1',
      );
      await factory.destroy();
    });
    expect(lines, isEmpty);
  });

  test('server-side warns naming each rate clamped to the 30s minimum',
      () async {
    final lines = await _captureLog(() async {
      final factory = ss.SplitFactory.create(
        'fake-api-key',
        ss.SplitClientConfig(
          sync: ss.SyncConfig(
            serviceEndpoints: ss.ServiceEndpoints(
                sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
            featureFlagsPollingRate: 5,
            segmentsPollingRate: 60,
            impressionsPushRate: 10,
            eventsPushRate: 1,
            streamingEnabled: false,
          ),
          installSignalHandler: false,
          logLevel: ss.LogLevel.warning,
        ),
      );
      await factory.destroy();
    });
    final warnings = lines.where((l) => l.contains('[WARNING]')).toList();
    expect(warnings.where((l) => l.contains('featureFlagsPollingRate')),
        hasLength(1));
    expect(
        warnings.where((l) => l.contains('impressionsPushRate')), hasLength(1));
    expect(warnings.where((l) => l.contains('eventsPushRate')), hasLength(1));
    expect(warnings.where((l) => l.contains('segmentsPollingRate')), isEmpty);
  });
}
