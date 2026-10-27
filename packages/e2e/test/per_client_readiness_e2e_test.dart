import 'dart:async';
import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// End-to-end coverage for spec §8.2: client-side readiness and UPDATE are
/// tracked per client. `clientReady = globalRulesReady && globalRbsReady &&
/// thisClientMembershipsReady`; a memberships change emits UPDATE only on
/// clients bound to the affected matching key; flag changes emit on every
/// client.

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

Future<bool> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(interval);
  }
  return condition();
}

MockResponse _membershipsResp({List<String> ms = const []}) => MockResponse()
    .setStatusCode(200)
    .setHeader('Content-Type', 'application/json')
    .setBody(jsonEncode({
      'ms': {'k': ms, 'cn': 1000},
      'ls': {'k': <String>[], 'cn': -1},
    }));

SplitClientConfig _config(String baseUrl,
        {int flagsPoll = 9999, int segmentsPoll = 9999}) =>
    SplitClientConfig(
      sync: SyncConfig(
        serviceEndpoints: ServiceEndpoints(
          sdkUrl: baseUrl,
          eventsUrl: baseUrl,
          authUrl: baseUrl,
          streamingUrl: baseUrl,
        ),
        featureFlagsPollingRate: flagsPoll,
        segmentsPollingRate: segmentsPoll,
        streamingEnabled: false,
      ),
      logLevel: LogLevel.warning,
    );

int _requestsFor(MockBackend backend, String key) =>
    backend.membershipsRequests.where((r) => r.path.endsWith('/$key')).length;

void main() {
  group('Per-client readiness and updates (spec §8.2)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        '(a) a shared client is not READY until its own /memberships '
        'response lands, even though the main client is already READY',
        () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMembershipsHandler((req, _) {
        final response = _membershipsResp();
        return req.path.endsWith('/slow_user')
            ? response.withDelay(const Duration(seconds: 4))
            : response;
      });

      final factory = SplitFactory.create('fake-api-key',
          _config(_baseUrl(backend)), const Key(matchingKey: 'main_user'));
      final main = factory.client();
      await main.whenReady().timeout(const Duration(seconds: 5));

      final slow = factory.client('slow_user');
      var slowReady = false;
      unawaited(slow.whenReady().then((_) => slowReady = true));

      await Future<void>.delayed(const Duration(seconds: 2));
      expect(slowReady, isFalse,
          reason: 'slow_user MUST NOT reach READY on main_user\'s memberships '
              '(its own /memberships/slow_user is still in flight)');

      await slow.whenReady().timeout(const Duration(seconds: 8));
      expect(slowReady, isTrue);

      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test(
        '(b) a memberships change for key B emits whenUpdated only on '
        'client B, not on client A', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMembershipsHandler((req, _) {
        if (req.path.endsWith('/user_b') &&
            _requestsFor(backend, 'user_b') > 1) {
          return _membershipsResp(ms: ['beta_users']);
        }
        return _membershipsResp();
      });

      final factory = SplitFactory.create(
          'fake-api-key',
          _config(_baseUrl(backend), segmentsPoll: 30),
          const Key(matchingKey: 'user_a'));
      final a = factory.client();
      final b = factory.client('user_b');
      await Future.wait([a.whenReady(), b.whenReady()])
          .timeout(const Duration(seconds: 5));

      final aUpdates = <List<String>>[];
      final bUpdates = <List<String>>[];
      final subA = a.whenUpdated().listen(aUpdates.add);
      final subB = b.whenUpdated().listen(bUpdates.add);

      expect(
          await _until(() => bUpdates.isNotEmpty,
              timeout: const Duration(seconds: 35)),
          isTrue,
          reason: 'user_b\'s membership change MUST emit UPDATE on client B');
      expect(bUpdates, [[]]);
      expect(_requestsFor(backend, 'user_a'), greaterThan(1),
          reason: 'user_a MUST have been polled too');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(aUpdates, isEmpty,
          reason: 'client A is bound to a different matching key and MUST '
              'NOT receive B\'s memberships UPDATE');

      await subA.cancel();
      await subB.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('(c) a flag change still emits whenUpdated on every client', () async {
      final newFlag = {
        'name': 'new_flag',
        'status': 'ACTIVE',
        'seed': 1234,
        'defaultTreatment': 'off',
        'trafficAllocation': 100,
        'trafficAllocationSeed': 1,
        'conditions': <dynamic>[],
        'configurations': <String, dynamic>{},
        'trafficTypeName': 'user',
        'killed': false,
        'changeNumber': 1001,
        'sets': <dynamic>[],
        'impressionsDisabled': false,
      };
      backend.stubSplitChangesHandler((req, callIndex) {
        final body = callIndex == 0
            ? {
                'ff': {'s': -1, 't': 1000, 'd': []},
                'rbs': {'s': -1, 't': 1000, 'd': []},
              }
            : {
                'ff': {
                  's': 1000,
                  't': 1001,
                  'd': [newFlag]
                },
                'rbs': {'s': 1000, 't': 1001, 'd': []},
              };
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(jsonEncode(body));
      });
      backend.stubMemberships();

      final factory = SplitFactory.create(
          'fake-api-key',
          _config(_baseUrl(backend), flagsPoll: 30),
          const Key(matchingKey: 'user_a'));
      final a = factory.client();
      final b = factory.client('user_b');
      await Future.wait([a.whenReady(), b.whenReady()])
          .timeout(const Duration(seconds: 5));

      final aUpdates = <List<String>>[];
      final bUpdates = <List<String>>[];
      final subA = a.whenUpdated().listen(aUpdates.add);
      final subB = b.whenUpdated().listen(bUpdates.add);

      expect(
          await _until(() => aUpdates.isNotEmpty && bUpdates.isNotEmpty,
              timeout: const Duration(seconds: 35)),
          isTrue,
          reason: 'a flag change MUST emit UPDATE on every client');
      expect(aUpdates, [
        ['new_flag']
      ]);
      expect(bUpdates, [
        ['new_flag']
      ]);

      await subA.cancel();
      await subB.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
