// A semver matcher whose runtime attribute value is not a valid semver MUST
// not match AND MUST log an ERROR (Node/JS parity, spec §5.5).
import 'dart:async';

import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

Map<String, dynamic> _matcherBase(String type) => {
      'keySelector': {'attribute': 'version'},
      'matcherType': type,
      'negate': false,
      'userDefinedSegmentMatcherData': null,
      'whitelistMatcherData': null,
      'unaryNumericMatcherData': null,
      'betweenMatcherData': null,
      'booleanMatcherData': null,
      'dependencyMatcherData': null,
      'stringMatcherData': {'value': '2.0.0'},
    };

Map<String, dynamic> _flag() => {
      'trafficTypeName': 'user',
      'name': 'semver_flag',
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 2,
      'status': 'ACTIVE',
      'killed': false,
      'defaultTreatment': 'off',
      'changeNumber': 1001,
      'algo': 2,
      'conditions': [
        {
          'conditionType': 'WHITELIST',
          'matcherGroup': {
            'combiner': 'AND',
            'matchers': [_matcherBase('EQUAL_TO_SEMVER')],
          },
          'partitions': [
            {'treatment': 'on', 'size': 100},
          ],
          'label': 'version equals 2.0.0',
        },
      ],
      'configurations': <String, dynamic>{},
      'sets': <dynamic>[],
    };

void main() {
  late MockBackend backend;

  setUp(() async {
    backend = MockBackend();
    await backend.start();
    backend.stubSplitChanges(splits: [_flag()]);
    backend.stubEvents();
  });

  tearDown(() async {
    await backend.shutdown();
  });

  test('non-semver attribute value: no match, ERROR logged', () async {
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
            logLevel: LogLevel.error,
          ),
        );
        final client = factory.client();
        await client.whenReady().timeout(const Duration(seconds: 5));
        expect(
            client.getTreatment('user-1', 'semver_flag',
                attributes: {'version': '2.0.0'}),
            'on');
        expect(
            client.getTreatment('user-1', 'semver_flag',
                attributes: {'version': 'banana'}),
            'off');
        await factory.destroy();
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => lines.add(line),
      ),
    );
    final errors = lines.where((l) => l.contains('[ERROR]')).toList();
    expect(errors, hasLength(1));
    expect(errors.single, contains('banana'));
    expect(errors.single, contains('EQUAL_TO_SEMVER'));
  });
}
