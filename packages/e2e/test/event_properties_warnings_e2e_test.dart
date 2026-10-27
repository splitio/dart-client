// track() event-properties validation (spec §16, JS parity):
//  - a value of an unsupported type (e.g. a list) is nulled, a WARNING naming
//    the property is logged, and track returns true;
//  - more than 300 properties logs a WARNING, the event is still tracked and
//    track returns true;
//  - exceeding 32 KB remains a hard failure: ERROR logged, track returns false.
import 'dart:async';

import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
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

  test(
      'server-side: list value nulled + WARNING, >300 props warns and tracks, '
      '>32KB fails', () async {
    final lines = <String>[];
    late List<Map<String, dynamic>> posted;
    final results = <bool>[];
    await runZoned(
      () async {
        final factory = ss.SplitFactory.create(
          'fake-api-key',
          ss.SplitClientConfig(
            sync: ss.SyncConfig(
              serviceEndpoints: ss.ServiceEndpoints(
                  sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
              featureFlagsPollingRate: 9999,
              segmentsPollingRate: 9999,
              impressionsPushRate: 9999,
              eventsPushRate: 9999,
              streamingEnabled: false,
            ),
            installSignalHandler: false,
            logLevel: ss.LogLevel.warning,
          ),
        );
        final client = factory.client();
        await client.whenReady().timeout(const Duration(seconds: 5));
        results.add(client.track('u1', 'user', 'evt_list', properties: {
          'list': [1, 2],
          'ok': 1,
        }));
        results.add(client.track('u1', 'user', 'evt_many',
            properties: {for (var i = 0; i < 301; i++) 'k$i': 'v'}));
        results.add(client.track('u1', 'user', 'evt_huge',
            properties: {'a': 'x' * (32 * 1024)}));
        await factory.destroy();
        posted = backend.postedEvents;
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );

    expect(results, [true, true, false]);

    final byType = {for (final e in posted) e['eventTypeId']: e};
    expect(byType.keys, unorderedEquals(['evt_list', 'evt_many']));
    expect(byType['evt_list']!['properties'], {'list': null, 'ok': 1});
    expect((byType['evt_many']!['properties'] as Map), hasLength(301));

    final warnings = lines.where((l) => l.contains('[WARNING]')).toList();
    expect(
        warnings
            .where((l) => l.contains('"list"') && l.contains('invalid type')),
        hasLength(1));
    expect(warnings.where((l) => l.contains('more than 300 properties')),
        hasLength(1));
    expect(
        lines.where((l) => l.contains('[ERROR]') && l.contains('32768 bytes')),
        hasLength(1));
  });

  test('client-side: >300 properties still tracked and track returns true',
      () async {
    final key = cs.Key(matchingKey: 'user_a');
    final factory = cs.SplitFactory.create(
      'fake-api-key',
      cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(
              sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
          featureFlagsPollingRate: 9999,
          streamingEnabled: false,
        ),
      ),
      key,
    );
    backend.stubMemberships();
    final client = factory.client(key);
    await client.whenReady().timeout(const Duration(seconds: 5));
    final ok = client.track('evt_many', 'user',
        properties: {for (var i = 0; i < 301; i++) 'k$i': 'v'});
    expect(ok, isTrue);
    await factory.destroy();
    expect(backend.postedEvents.map((e) => e['eventTypeId']), ['evt_many']);
  });
}
