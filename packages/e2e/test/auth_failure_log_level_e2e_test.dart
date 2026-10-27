// A 401/403 on the initial sync MUST be logged at ERROR level (spec §10.3),
// like every failed data fetch. Asserted on both flavors via captured log
// output while the MockBackend answers /splitChanges with 401.
import 'dart:async';

import 'package:mock_http_server/mock_http_server.dart';
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
    backend.stubSplitChangesHandler(
        (_, __) => MockResponse().setStatusCode(401).setBody('unauthorized'));
    backend.stubEvents();
  });

  tearDown(() async {
    await backend.shutdown();
  });

  test('server-side: 401 on initial sync logs ERROR', () async {
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
          logLevel: ss.LogLevel.warning,
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      await factory.destroy();
    });
    expect(lines.where((l) => l.contains('[ERROR]') && l.contains('401')),
        isNotEmpty);
    expect(lines.where((l) => l.contains('[WARNING]') && l.contains('401')),
        isEmpty);
  });

  test('client-side: 401 on initial sync logs ERROR', () async {
    final lines = await _captureLog(() async {
      final factory = cs.SplitFactory.create(
        'fake-api-key',
        cs.SplitClientConfig(
          sync: cs.SyncConfig(
            serviceEndpoints: cs.ServiceEndpoints(
                sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
            streamingEnabled: false,
          ),
          logLevel: cs.LogLevel.warning,
        ),
        'user-1',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      await factory.destroy();
    });
    expect(lines.where((l) => l.contains('[ERROR]') && l.contains('401')),
        isNotEmpty);
    expect(lines.where((l) => l.contains('[WARNING]') && l.contains('401')),
        isEmpty);
  });
}
