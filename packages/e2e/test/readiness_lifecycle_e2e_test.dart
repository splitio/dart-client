import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Polls [condition] until it is true or [timeout] elapses.
/// Returns `true` if [condition] became true before the deadline.
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

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

void main() {
  group('Readiness lifecycle e2e', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test('whenReady completes after SDK initializes', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      backend.stubAuth();
      backend.stubStreaming();

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = const Key(matchingKey: 'user1');
      final factory = SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);

      await expectLater(
          client.whenReady().timeout(const Duration(seconds: 5)), completes);

      await factory.destroy();
    });

    test('whenTimeout completes when initial sync fails within readyTimeout',
        () async {
      // Stub /splitChanges to always return 500 so initialSync never completes
      // and READY never fires. After readyTimeout (1s), whenTimeout() MUST resolve.
      backend.stubSplitChangesHandler((_, __) =>
          MockResponse().setStatusCode(500).setBody('internal error'));
      backend.stubMemberships();
      // Disable push so streaming never starts — keeps the test scope narrow.
      backend.stubAuth(pushEnabled: false);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          readyTimeout: 1,
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = const Key(matchingKey: 'user1');
      final factory = SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);

      // whenTimeout() MUST complete after readyTimeout (1s) elapses.
      await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 5)), completes);

      await factory.destroy();
    });

    test(
        'readyTimeout is measured from factory creation, not after initial sync',
        () async {
      // Initial /splitChanges takes 3s; readyTimeout is 1s. TIMEOUT MUST fire
      // ~1s after create (spec §8.2), while the initial sync is still in flight.
      backend.stubSplitChangesHandler((_, __) => MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode({
            'ff': {'s': -1, 't': 1000, 'd': []},
            'rbs': {'s': -1, 't': 1000, 'd': []},
          }))
          .withDelay(const Duration(seconds: 3)));
      backend.stubMemberships();
      backend.stubAuth(pushEnabled: false);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          readyTimeout: 1,
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = const Key(matchingKey: 'user1');
      final factory = SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);

      await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 2)), completes);

      await factory.destroy();
    });

    test(
        'READY fires from a later poll after the initial sync fails '
        '(spec §8.2)', () async {
      // First /splitChanges returns 500 so initialSync() fails and READY
      // does not fire on that path. whenTimeout() MUST still fire after
      // readyTimeout. Later polls return 200 with a real flag — READY MUST
      // fire from that later poll (spec §8.2), and evaluations MUST stop
      // returning 'control' once it does.
      final flagPayload = {
        'trafficTypeName': 'user',
        'name': 'late_sync_flag',
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
      backend.stubSplitChangesHandler((_, callIndex) {
        if (callIndex == 0) {
          return MockResponse().setStatusCode(500).setBody('internal error');
        }
        final body = jsonEncode({
          'ff': {
            's': -1,
            't': 1001,
            'd': [flagPayload],
          },
          'rbs': {'s': -1, 't': 1001, 'd': []},
        });
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(body);
      });
      backend.stubMemberships();

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          readyTimeout: 1,
          // Clamped up to the 30s floor by SyncConfig.normalized() — this
          // test waits out a real poll cycle rather than special-casing a
          // faster rate.
          featureFlagsPollingRate: 1,
          segmentsPollingRate: 1,
          // Streaming is disabled so the organic poll fallback (started
          // directly by SyncManager.startStreaming() when no
          // StreamingManager is wired) runs without depending on a
          // separate, already-tracked bug where polling never starts if
          // streaming never connects.
          streamingEnabled: false,
        ),
        logLevel: LogLevel.warning,
      );

      final key = const Key(matchingKey: 'user1');
      final factory = SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);

      await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 5)), completes,
          reason: 'whenTimeout() MUST fire after readyTimeout even though '
              'the initial sync is still failing');

      expect(client.getTreatment('late_sync_flag'), equals('control'),
          reason: 'Evaluations before READY MUST return control');

      await expectLater(
          client.whenReady().timeout(const Duration(seconds: 45)), completes,
          reason: 'whenReady() MUST complete once a later poll succeeds, '
              'even though the initial sync failed (spec §8.2)');

      expect(client.getTreatment('late_sync_flag'), equals('on'),
          reason: 'Once READY fires from a later poll, evaluations MUST '
              'reflect the data that poll loaded');

      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('whenUpdated emits changed flags when they change via streaming',
        () async {
      // The first /splitChanges call (initial sync) returns since=-1 / t=1000
      // with no flags. The second call (catch-up after SPLIT_UPDATE) returns
      // a NEW flag at t=1001 so FlagsFetcher.onUpdate fires with changed flags.
      final flagPayload = {
        'name': 'my_feature',
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
        if (callIndex == 0) {
          // Initial fetch: empty flags at t=1000.
          final body = jsonEncode({
            'ff': {'s': -1, 't': 1000, 'd': []},
            'rbs': {'s': -1, 't': 1000, 'd': []},
          });
          return MockResponse()
              .setStatusCode(200)
              .setHeader('Content-Type', 'application/json')
              .setBody(body);
        }
        // Catch-up fetch after SPLIT_UPDATE: new flag at t=1001.
        final body = jsonEncode({
          'ff': {
            's': 1000,
            't': 1001,
            'd': [flagPayload]
          },
          'rbs': {'s': 1000, 't': 1001, 'd': []},
        });
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(body);
      });
      backend.stubMemberships();
      backend.stubAuth();
      // Push a SPLIT_UPDATE with a higher change number to trigger a re-sync.
      backend.stubStreaming(events: [
        MockBackend.splitUpdateEvent(changeNumber: 1001),
      ]);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final key = const Key(matchingKey: 'user1');
      final factory = SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);

      final updatedArgs = <List<String>>[];
      final sub = client.whenUpdated().listen(updatedArgs.add);

      // Wait for SDK to be ready first.
      await client.whenReady().timeout(const Duration(seconds: 5));

      // Wait for the catch-up fetch to complete (second /splitChanges call).
      expect(
          await _until(() => backend.splitChangesRequests.length > 1), isTrue,
          reason: 'SPLIT_UPDATE MUST trigger a re-sync (second /splitChanges)');

      // whenUpdated emits when FlagsFetcher.onUpdate is invoked with non-empty
      // changed flags from the catch-up fetch.
      expect(await _until(() => updatedArgs.isNotEmpty), isTrue,
          reason: 'whenUpdated MUST emit when flags change via streaming');
      expect(updatedArgs.first, equals(['my_feature']));

      await sub.cancel();
      await factory.destroy();
    });

    test('factory.destroy stops polling before final flush', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      backend.stubAuth(pushEnabled: false); // Disable push to isolate polling

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 999999, // Disable automatic polling
          segmentsPollingRate: 999999,
          impressionsPushRate: 999999,
          eventsPushRate: 999999,
        ),
        logLevel: LogLevel.error, // Suppress warnings
      );

      final key = const Key(matchingKey: 'user1');
      final factory = SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);

      await client.whenReady().timeout(const Duration(seconds: 5));

      // Track an event to queue events for flush-on-destroy
      client.track('click', 'user');

      // Initial sync already fired one /splitChanges
      final splitChangesCountBeforeDestroy =
          backend.splitChangesRequests.length;
      expect(splitChangesCountBeforeDestroy, greaterThanOrEqualTo(1),
          reason: 'At least one initial sync /splitChanges should have fired');

      await factory.destroy();

      // After destroy completes, no new /splitChanges polls should fire.
      await Future.delayed(const Duration(milliseconds: 500));
      expect(backend.splitChangesRequests.length,
          equals(splitChangesCountBeforeDestroy),
          reason:
              'No additional /splitChanges polls should fire after destroy');

      // At least one final POST for /events/bulk (the tracked event)
      expect(backend.eventRequests.length, greaterThanOrEqualTo(1),
          reason: 'At least one /events/bulk flush should have fired');
    });

    test('client.destroy() flushes events and impressions (spec §8.5)',
        () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      backend.stubAuth(pushEnabled: false);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 999999,
          segmentsPollingRate: 999999,
          impressionsPushRate: 999999,
          eventsPushRate: 999999,
        ),
        logLevel: LogLevel.error,
      );

      final key = const Key(matchingKey: 'user1');
      final factory = SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);

      await client.whenReady().timeout(const Duration(seconds: 5));

      client.track('click', 'user');
      client.getTreatment('test_flag_whitelist');

      final splitChangesBefore = backend.splitChangesRequests.length;
      final eventsBefore = backend.eventRequests.length;
      final impressionsBefore = backend.impressionRequests.length;

      // Per spec §8.5, client.destroy() MUST flush queued events and
      // impressions before the returned Future resolves. It MUST NOT stop
      // the factory sync pipeline.
      await client.destroy();

      expect(backend.eventRequests.length, greaterThan(eventsBefore),
          reason: 'client.destroy() MUST flush queued events');
      expect(backend.impressionRequests.length, greaterThan(impressionsBefore),
          reason: 'client.destroy() MUST flush queued impressions');
      expect(backend.splitChangesRequests.length, equals(splitChangesBefore),
          reason:
              'client.destroy() MUST NOT stop or trigger sync (spec §8.5 Option A)');
    });

    test('client.destroy() closes only that client\'s whenUpdated stream',
        () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      backend.stubAuth(pushEnabled: false);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 999999,
          segmentsPollingRate: 999999,
          impressionsPushRate: 999999,
          eventsPushRate: 999999,
        ),
        logLevel: LogLevel.error,
      );

      final factory = SplitFactory.create(
          'fake-api-key', config, const Key(matchingKey: 'user1'));
      final kept = factory.client();
      final destroyed = factory.client('user2');
      await kept.whenReady().timeout(const Duration(seconds: 5));

      var keptDone = false;
      var destroyedDone = false;
      kept.whenUpdated().listen(null, onDone: () => keptDone = true);
      destroyed.whenUpdated().listen(null, onDone: () => destroyedDone = true);

      // Spec §8.2: destroying a client MUST close its whenUpdated() stream,
      // without affecting other clients of the same factory.
      await destroyed.destroy();
      expect(await _until(() => destroyedDone), isTrue,
          reason: 'client.destroy() MUST close its whenUpdated() stream');
      expect(keptDone, isFalse,
          reason: 'other clients\' whenUpdated() MUST stay open');

      await factory.destroy();
      expect(await _until(() => keptDone), isTrue,
          reason: 'factory.destroy() MUST close every whenUpdated() stream');
    });

    test('a concurrent factory.destroy() waits for the in-flight final flush',
        () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      backend.stubAuth(pushEnabled: false);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 999999,
          segmentsPollingRate: 999999,
          impressionsPushRate: 999999,
          eventsPushRate: 999999,
        ),
        logLevel: LogLevel.error,
      );

      final key = const Key(matchingKey: 'user1');
      final factory = SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));
      client.track('click', 'user');

      // Two callers destroy at once (e.g. app code and a shutdown hook). The
      // second call MUST NOT resolve before the first call's flush is done.
      final first = factory.destroy();
      await factory.destroy();

      expect(backend.eventRequests, isNotEmpty,
          reason: 'second destroy() resolved before the final flush');
      await first;
    });

    test('destroy during initial sync leaves no periodic timers running',
        () async {
      // destroy() lands while the initial /splitChanges is still in flight.
      // When that fetch resolves, the SDK MUST NOT start polling or recorder
      // timers on the destroyed factory.
      backend.stubSplitChangesHandler((_, __) => MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode({
            'ff': {'s': -1, 't': 1000, 'd': []},
            'rbs': {'s': -1, 't': 1000, 'd': []},
          }))
          .withDelay(const Duration(milliseconds: 500)));
      backend.stubMemberships();
      backend.stubAuth(pushEnabled: false);

      final baseUrl = _baseUrl(backend);
      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: LogLevel.warning,
      );

      final periodicTimers = <Timer>[];
      final uncaught = <Object>[];

      await runZonedGuarded(
        () async {
          final factory = SplitFactory.create(
              'fake-api-key', config, const Key(matchingKey: 'user1'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await factory.destroy();
          // Let the in-flight initial sync finish after destroy. The closed
          // http client makes the fetchers retry with 1s + 2s backoff.
          await Future<void>.delayed(const Duration(seconds: 4));
        },
        (error, _) => uncaught.add(error),
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, period, f) {
            final timer = parent.createPeriodicTimer(zone, period, f);
            periodicTimers.add(timer);
            return timer;
          },
        ),
      );

      final active = periodicTimers.where((t) => t.isActive).toList();
      for (final t in active) {
        t.cancel();
      }
      expect(active, isEmpty);
      expect(uncaught, isEmpty);
    });
  });
}
