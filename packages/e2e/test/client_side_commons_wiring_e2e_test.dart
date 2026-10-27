// Client-side wiring of commons fixes (spec §14, §16, §19.4): polling-rate
// normalization without a minimum (and no clamping warning), flag-name
// validation logged at ERROR, semver attribute errors logged at ERROR, and
// event-properties warnings that still track.
import 'dart:async';

import 'package:splitio_client_side/splitio_client_side.dart';
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

SplitFactory _factory(MockBackend backend, Key key,
    {int rate = 9999, LogLevel level = LogLevel.warning}) {
  return SplitFactory.create(
    'fake-api-key',
    SplitClientConfig(
      sync: SyncConfig(
        serviceEndpoints: ServiceEndpoints(
            sdkUrl: _baseUrl(backend), eventsUrl: _baseUrl(backend)),
        featureFlagsPollingRate: rate,
        streamingEnabled: false,
      ),
      logLevel: level,
    ),
    key,
  );
}

void main() {
  late MockBackend backend;
  final key = Key(matchingKey: 'user_a');

  setUp(() async {
    backend = MockBackend();
    await backend.start();
    backend.stubSplitChanges(splits: [_flag()]);
    backend.stubEvents();
    backend.stubMemberships();
  });

  tearDown(() async {
    await backend.shutdown();
  });

  test('featureFlagsPollingRate below 30s is honoured with no clamping warning',
      () async {
    final lines = await _captureLog(() async {
      final factory = _factory(backend, key, rate: 1);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      await factory.destroy();
    });
    expect(backend.splitChangesRequests.length, greaterThanOrEqualTo(3));
    expect(lines.where((l) => l.contains('featureFlagsPollingRate')), isEmpty);
  });

  test('empty name in getTreatments list logs ERROR', () async {
    final lines = await _captureLog(() async {
      final factory = _factory(backend, key);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));
      expect(client.getTreatments(['semver_flag', '']).keys, ['semver_flag']);
      await factory.destroy();
    });
    expect(
        lines.where((l) =>
            l.contains('[ERROR]') && l.contains('empty feature flag name')),
        hasLength(1));
    expect(
        lines.where(
            (l) => l.contains('[WARNING]') && l.contains('empty feature flag')),
        isEmpty);
  });

  test('non-semver attribute value: no match, ERROR logged', () async {
    final lines = await _captureLog(() async {
      final factory = _factory(backend, key, level: LogLevel.error);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));
      expect(
          client.getTreatment('semver_flag', attributes: {'version': '2.0.0'}),
          'on');
      expect(
          client.getTreatment('semver_flag', attributes: {'version': 'banana'}),
          'off');
      await factory.destroy();
    });
    final errors = lines.where((l) => l.contains('[ERROR]')).toList();
    expect(errors, hasLength(1));
    expect(errors.single, contains('banana'));
    expect(errors.single, contains('EQUAL_TO_SEMVER'));
  });

  test('list property value warns and track returns true; 301 props warns',
      () async {
    late bool listOk;
    late bool manyOk;
    final lines = await _captureLog(() async {
      final factory = _factory(backend, key);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));
      listOk = client.track('evt_list', 'user', properties: {
        'list': [1, 2],
        'ok': 1,
      });
      manyOk = client.track('evt_many', 'user',
          properties: {for (var i = 0; i < 301; i++) 'k$i': 'v'});
      await factory.destroy();
    });
    expect(listOk, isTrue);
    expect(manyOk, isTrue);
    final warnings = lines.where((l) => l.contains('[WARNING]')).toList();
    expect(
        warnings
            .where((l) => l.contains('"list"') && l.contains('invalid type')),
        hasLength(1));
    expect(warnings.where((l) => l.contains('more than 300 properties')),
        hasLength(1));
    final byType = {for (final e in backend.postedEvents) e['eventTypeId']: e};
    expect(byType['evt_list']!['properties'], {'list': null, 'ok': 1});
  });
}
