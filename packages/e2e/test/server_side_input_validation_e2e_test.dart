import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

MockResponse _emptySplitChanges() => MockResponse()
    .setStatusCode(200)
    .setHeader('Content-Type', 'application/json')
    .setBody(jsonEncode({
      'ff': {'s': -1, 't': 1000, 'd': []},
      'rbs': {'s': -1, 't': 1000, 'd': []},
    }));

SplitClientConfig _config(MockBackend backend) {
  final baseUrl = _baseUrl(backend);
  return SplitClientConfig(
    sync: SyncConfig(
      serviceEndpoints: ServiceEndpoints(sdkUrl: baseUrl, eventsUrl: baseUrl),
      featureFlagsPollingRate: 9999,
      segmentsPollingRate: 9999,
      impressionsPushRate: 9999,
      eventsPushRate: 9999,
    ),
    installSignalHandler: false,
    logLevel: LogLevel.error,
  );
}

void main() {
  group('Server-side input validation e2e — invalid key type', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
      backend.stubSplitChangesHandler((_, __) => _emptySplitChanges());
      backend.stubEvents();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'getTreatment/getTreatments/getTreatmentWithConfig/track with a '
        'Map or Object key fail open to control/false instead of throwing',
        () async {
      final factory = SplitFactory.create('fake-api-key', _config(backend));
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      final mapKey = <String, String>{'not': 'a key'};
      final objectKey = Object();

      expect(() => client.getTreatment(mapKey, 'some_flag'), returnsNormally);
      expect(client.getTreatment(mapKey, 'some_flag'), 'control');
      expect(client.getTreatment(objectKey, 'some_flag'), 'control');

      final withConfig = client.getTreatmentWithConfig(mapKey, 'some_flag');
      expect(withConfig.treatment, 'control');
      expect(withConfig.config, isNull);

      expect(client.getTreatments(mapKey, ['flag_a', 'flag_b']),
          {'flag_a': 'control', 'flag_b': 'control'});

      expect(
          client.getTreatmentsWithConfig(mapKey, ['flag_a', 'flag_b']).map(
              (k, v) => MapEntry(k, v.treatment)),
          {'flag_a': 'control', 'flag_b': 'control'});

      expect(client.getTreatmentsByFlagSets(mapKey, ['set_a']), isEmpty);
      expect(
          client.getTreatmentsWithConfigByFlagSets(mapKey, ['set_a']), isEmpty);

      expect(() => client.track(mapKey, 'user', 'click'), returnsNormally);
      expect(client.track(mapKey, 'user', 'click'), isFalse);
      expect(client.track(objectKey, 'user', 'click'), isFalse);

      await factory.destroy();
      expect(backend.postedEvents, isEmpty,
          reason: 'invalid-key track() calls must never reach /events/bulk');
    });
  });
}
