// The client-side READY log MUST NOT include the matching key at INFO: the
// key is an end-user identifier (PII). JS parity: javascript-commons logs
// "SDK client is ready" with no key.
import 'dart:async';
import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart' as cs;
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
  });

  tearDown(() async {
    await backend.shutdown();
  });

  test('client-side READY log at INFO does not contain the matching key',
      () async {
    const key = 'pii_user@example.com';
    backend.stubFromFixtures(
      '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
    );
    final lines = await _captureLog(() async {
      final base = _baseUrl(backend);
      final factory = cs.SplitFactory.create(
        'fake-api-key',
        cs.SplitClientConfig(
          sync: cs.SyncConfig(
            serviceEndpoints:
                cs.ServiceEndpoints(sdkUrl: base, eventsUrl: base),
            featureFlagsPollingRate: 9999,
            segmentsPollingRate: 9999,
            impressionsPushRate: 9999,
            eventsPushRate: 9999,
          ),
          logLevel: cs.LogLevel.info,
        ),
        key,
      );
      await factory.client().whenReady().timeout(const Duration(seconds: 5));
      await factory.destroy();
    });

    expect(lines.where((l) => l.contains('SDK client is ready')), isNotEmpty);
    expect(
        lines.where((l) => l.contains('[INFO]') && l.contains(key)), isEmpty);
  });
}
