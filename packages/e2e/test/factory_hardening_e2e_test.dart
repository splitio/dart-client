// Spec §7 / §7.1: manager behavior after factory destroy, duplicate-factory
// warning, and `SplitFactory.client(key)` validation (client-side).
import 'dart:async';

import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

Future<bool> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return condition();
}

Map<String, dynamic> _flag(String name) => {
      'trafficTypeName': 'user',
      'name': name,
      'trafficAllocation': 100,
      'trafficAllocationSeed': 123456,
      'seed': 987654,
      'status': 'ACTIVE',
      'killed': false,
      'defaultTreatment': 'off',
      'changeNumber': 1001,
      'algo': 2,
      'conditions': [
        {
          'conditionType': 'ROLLOUT',
          'matcherGroup': {
            'combiner': 'AND',
            'matchers': [
              {
                'keySelector': null,
                'matcherType': 'ALL_KEYS',
                'negate': false,
                'userDefinedSegmentMatcherData': null,
                'whitelistMatcherData': null,
                'unaryNumericMatcherData': null,
                'betweenMatcherData': null,
                'booleanMatcherData': null,
                'dependencyMatcherData': null,
                'stringMatcherData': null,
              }
            ],
          },
          'partitions': [
            {'treatment': 'on', 'size': 100},
          ],
          'label': 'default rule',
        }
      ],
      'configurations': <String, dynamic>{},
      'sets': <dynamic>[],
    };

/// Captures everything the SDK logger prints (it writes via `print`).
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

cs.SplitClientConfig _csConfig(MockBackend backend) {
  final baseUrl = _baseUrl(backend);
  return cs.SplitClientConfig(
    sync: cs.SyncConfig(
      serviceEndpoints: cs.ServiceEndpoints(
        sdkUrl: baseUrl,
        eventsUrl: baseUrl,
        authUrl: baseUrl,
        streamingUrl: baseUrl,
      ),
      readyTimeout: 1,
      featureFlagsPollingRate: 9999,
      segmentsPollingRate: 9999,
      streamingEnabled: false,
    ),
    logLevel: cs.LogLevel.warning,
  );
}

ss.SplitClientConfig _ssConfig(MockBackend backend) {
  final baseUrl = _baseUrl(backend);
  return ss.SplitClientConfig(
    sync: ss.SyncConfig(
      serviceEndpoints: ss.ServiceEndpoints(
        sdkUrl: baseUrl,
        eventsUrl: baseUrl,
        authUrl: baseUrl,
        streamingUrl: baseUrl,
      ),
      readyTimeout: 5,
      featureFlagsPollingRate: 9999,
      segmentsPollingRate: 9999,
      streamingEnabled: false,
    ),
    installSignalHandler: false,
    logLevel: ss.LogLevel.warning,
  );
}

const _destroyedMsg = 'Client has already been destroyed - no calls possible.';

void main() {
  late MockBackend backend;

  setUp(() async {
    backend = MockBackend();
    await backend.start();
    backend.stubSplitChanges(splits: [_flag('f1')], since: 1000);
    backend.stubMemberships();
    backend.stubSegmentChanges();
  });

  tearDown(() async {
    await backend.shutdown();
  });

  group('SplitManager after factory.destroy() (spec §7.1)', () {
    test('client-side: returns null/empty and logs ERROR per method', () async {
      final logs = await _captureLog(() async {
        final factory = cs.SplitFactory.create(
            'cs-destroy-mgr-key', _csConfig(backend), 'user');
        await factory.client().whenReady().timeout(const Duration(seconds: 5));
        final manager = factory.manager();
        expect(manager.names(), ['f1']);
        expect(manager.splits(), hasLength(1));
        expect(manager.split('f1'), isNotNull);

        await factory.destroy();

        expect(manager.split('f1'), isNull);
        expect(manager.splits(), isEmpty);
        expect(manager.names(), isEmpty);
      });
      for (final m in ['split', 'splits', 'names']) {
        expect(
            logs.where((l) =>
                l.contains('[ERROR]') && l.contains('$m: $_destroyedMsg')),
            isNotEmpty,
            reason: 'expected "$m: $_destroyedMsg" ERROR log, got $logs');
      }
    });

    test('client-side: destroying only a client does not affect the manager',
        () async {
      final factory = cs.SplitFactory.create(
          'cs-destroy-client-key', _csConfig(backend), 'user');
      await factory.client().whenReady().timeout(const Duration(seconds: 5));
      final other = factory.client('other');
      await other.destroy();
      expect(factory.manager().names(), ['f1']);
      await factory.destroy();
    });

    test('server-side: returns null/empty and logs ERROR per method', () async {
      final logs = await _captureLog(() async {
        final factory =
            ss.SplitFactory.create('ss-destroy-mgr-key', _ssConfig(backend));
        await factory.client().whenReady().timeout(const Duration(seconds: 5));
        final manager = factory.manager();
        expect(manager.names(), ['f1']);

        await factory.destroy();

        expect(manager.split('f1'), isNull);
        expect(manager.splits(), isEmpty);
        expect(manager.names(), isEmpty);
      });
      for (final m in ['split', 'splits', 'names']) {
        expect(
            logs.where((l) =>
                l.contains('[ERROR]') && l.contains('$m: $_destroyedMsg')),
            isNotEmpty,
            reason: 'expected "$m: $_destroyedMsg" ERROR log, got $logs');
      }
    });
  });

  group('Duplicate factory warning (spec §7)', () {
    test('same SDK key warns with the live count; destroy decrements',
        () async {
      final logs = await _captureLog(() async {
        final a = cs.SplitFactory.create('dup-key-a', _csConfig(backend), 'u1');
        final b = ss.SplitFactory.create('dup-key-a', _ssConfig(backend));
        await a.destroy();
        await b.destroy();
        await a.destroy(); // idempotent: MUST NOT double-decrement
        final c = cs.SplitFactory.create('dup-key-a', _csConfig(backend), 'u1');
        await c.destroy();
      });
      final warnings = logs
          .where((l) =>
              l.contains('[WARNING]') &&
              l.contains(
                  'We recommend keeping only one instance of the factory'))
          .toList();
      expect(warnings, hasLength(1), reason: '$logs');
      expect(warnings.single,
          contains('You already have 1 factory/ies with this SDK Key'));
    });

    test('a different SDK key warns that another instance exists', () async {
      final logs = await _captureLog(() async {
        final a =
            cs.SplitFactory.create('dup-key-b1', _csConfig(backend), 'u1');
        final b =
            cs.SplitFactory.create('dup-key-b2', _csConfig(backend), 'u1');
        await a.destroy();
        await b.destroy();
      });
      expect(
          logs.where((l) =>
              l.contains('[WARNING]') &&
              l.contains('You already have an instance of the Split factory')),
          hasLength(1),
          reason: '$logs');
    });

    test('NoOp factories are not counted', () async {
      final logs = await _captureLog(() async {
        final noop = cs.SplitFactory.create('', _csConfig(backend), 'u1');
        final a = cs.SplitFactory.create('dup-key-c', _csConfig(backend), 'u1');
        await noop.destroy();
        await a.destroy();
      });
      expect(logs.where((l) => l.contains('We recommend keeping only one')),
          isEmpty,
          reason: '$logs');
    });
  });

  group('factory.client(key) validation — client-side (spec §7, §16)', () {
    late cs.SplitFactory factory;

    setUp(() async {
      factory = cs.SplitFactory.create(
          'cs-client-key-val', _csConfig(backend), 'main_user');
      await factory.client().whenReady().timeout(const Duration(seconds: 5));
    });

    tearDown(() async {
      await factory.destroy();
    });

    int membershipsFor(String key) => backend.membershipsRequests
        .where((r) => r.path.endsWith('/$key'))
        .length;

    for (final bad in <Object>[
      '',
      '   ',
      'x' * 251,
      <int>[1]
    ]) {
      test(
          'invalid key (${bad.toString().length > 20 ? 'long' : bad}) returns '
          'a NoOp client, logs ERROR, fetches nothing', () async {
        final before = backend.membershipsRequests.length;
        late cs.SplitClient client;
        final logs = await _captureLog(() => client = factory.client(bad));
        expect(logs.where((l) => l.contains('[ERROR]')), isNotEmpty,
            reason: '$logs');
        expect(client, isNot(same(factory.client())));
        expect(client.getTreatment('f1'), 'control');
        expect(client.track('user', 'evt'), isFalse);
        var ready = false;
        unawaited(client.whenReady().then((_) => ready = true));
        await client.whenTimeout().timeout(const Duration(seconds: 3));
        expect(ready, isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(backend.membershipsRequests.length, before);
      });
    }

    test('invalid bucketing key returns a NoOp client', () async {
      final client =
          factory.client(const cs.Key(matchingKey: 'ok', bucketingKey: ' '));
      expect(client.getTreatment('f1'), 'control');
      expect(membershipsFor('ok'), 0);
    });

    test('num key warns and is a distinct client for its toString()', () async {
      late cs.SplitClient client;
      final logs = await _captureLog(() => client = factory.client(42));
      expect(logs.where((l) => l.contains('[WARNING]')), isNotEmpty,
          reason: '$logs');
      expect(client, isNot(same(factory.client())));
      expect(await _until(() => membershipsFor('42') == 1), isTrue);
      expect(client, same(factory.client('42')));
      await client.whenReady().timeout(const Duration(seconds: 5));
      expect(client.getTreatment('f1'), 'on');
    });

    test('null key returns the main client', () {
      expect(factory.client(null), same(factory.client()));
    });
  });
}
