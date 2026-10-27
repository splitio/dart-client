import 'dart:async';
import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

MockResponse _emptySplitChanges({Duration? delay}) {
  final response = MockResponse()
      .setStatusCode(200)
      .setHeader('Content-Type', 'application/json')
      .setBody(jsonEncode({
        'ff': {'s': -1, 't': 1000, 'd': []},
        'rbs': {'s': -1, 't': 1000, 'd': []},
      }));
  return delay == null ? response : response.withDelay(delay);
}

SplitClientConfig _config(
  MockBackend backend, {
  int readyTimeout = 10,
  int featureFlagsPollingRate = 9999,
  int segmentsPollingRate = 9999,
  bool streamingEnabled = true,
}) {
  final baseUrl = _baseUrl(backend);
  return SplitClientConfig(
    sync: SyncConfig(
      serviceEndpoints: ServiceEndpoints(
        sdkUrl: baseUrl,
        eventsUrl: baseUrl,
        authUrl: baseUrl,
        streamingUrl: baseUrl,
      ),
      readyTimeout: readyTimeout,
      featureFlagsPollingRate: featureFlagsPollingRate,
      segmentsPollingRate: segmentsPollingRate,
      streamingEnabled: streamingEnabled,
    ),
    installSignalHandler: false,
    logLevel: LogLevel.warning,
  );
}

/// Polls [condition] until it is true or [timeout] elapses. Returns `true` if
/// [condition] became true before the deadline, `false` otherwise. Call sites
/// MUST assert on the returned value so a genuinely-unmet condition FAILS the
/// test rather than silently passing on a timeout/expect race.
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

void main() {
  group('Server-side lifecycle e2e', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'readyTimeout is measured from factory creation, not after initial sync',
        () async {
      // Initial /splitChanges takes 3s; readyTimeout is 1s. TIMEOUT MUST fire
      // ~1s after create (spec §8.2), while the initial sync is still in flight.
      backend.stubSplitChangesHandler(
          (_, __) => _emptySplitChanges(delay: const Duration(seconds: 3)));

      final factory = SplitFactory.create(
          'fake-api-key', _config(backend, readyTimeout: 1));
      final client = factory.client();

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

      final factory = SplitFactory.create(
        'fake-api-key',
        _config(
          backend,
          readyTimeout: 1,
          // Clamped up to the 30s floor by SyncConfig.normalized() — this
          // test waits out a real poll cycle rather than special-casing a
          // faster rate.
          featureFlagsPollingRate: 1,
          segmentsPollingRate: 1,
          // Streaming disabled so the organic poll fallback runs directly,
          // without depending on a separate, already-tracked bug where
          // polling never starts if streaming never connects.
          streamingEnabled: false,
        ),
      );
      final client = factory.client();

      await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 5)), completes,
          reason: 'whenTimeout() MUST fire after readyTimeout even though '
              'the initial sync is still failing');

      expect(client.getTreatment('user1', 'late_sync_flag'), equals('control'),
          reason: 'Evaluations before READY MUST return control');

      await expectLater(
          client.whenReady().timeout(const Duration(seconds: 45)), completes,
          reason: 'whenReady() MUST complete once a later poll succeeds, '
              'even though the initial sync failed (spec §8.2)');

      expect(client.getTreatment('user1', 'late_sync_flag'), equals('on'),
          reason: 'Once READY fires from a later poll, evaluations MUST '
              'reflect the data that poll loaded');

      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('client.destroy() closes the whenUpdated stream', () async {
      backend.stubSplitChangesHandler((_, __) => _emptySplitChanges());

      final factory = SplitFactory.create('fake-api-key', _config(backend));
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      // Spec §8.2: destroying the client MUST close its whenUpdated() stream.
      await expectLater(
          client
              .destroy()
              .then((_) => client.whenUpdated().toList())
              .timeout(const Duration(seconds: 2)),
          completion(isEmpty));

      await factory.destroy();
    });

    test('destroy during initial sync leaves no periodic timers running',
        () async {
      // destroy() lands while the initial /splitChanges is still in flight.
      // When that fetch resolves, the SDK MUST NOT start polling or recorder
      // timers on the destroyed factory.
      backend.stubSplitChangesHandler((_, __) =>
          _emptySplitChanges(delay: const Duration(milliseconds: 500)));

      final periodicTimers = <Timer>[];
      final uncaught = <Object>[];

      await runZonedGuarded(
        () async {
          final factory = SplitFactory.create('fake-api-key', _config(backend));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await factory.destroy();
          // Let the in-flight initial sync finish after destroy. The closed
          // http client makes FlagsFetcher retry with 1s + 2s backoff.
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

    test('a concurrent destroy() waits for the in-flight final flush',
        () async {
      // A SIGTERM handler and app code can both call destroy(). The second
      // call MUST NOT resolve (and let the signal handler exit the process)
      // before the first call's final flush is done.
      backend.stubSplitChangesHandler((_, __) => _emptySplitChanges());
      backend.stubEvents();

      final factory = SplitFactory.create('fake-api-key', _config(backend));
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));
      client.track('user1', 'user', 'click');

      final first = factory.destroy();
      await factory.destroy();

      expect(backend.eventRequests, isNotEmpty,
          reason: 'second destroy() resolved before the final flush');
      await first;
    });

    test(
        'destroy() while push is up does not leave a restarted poll timer '
        'running', () async {
      // While push is up, poll timers are stopped. StreamingManager.stop()
      // (triggered by factory.destroy()) tears down the socket, which was
      // up, so the FSM emits NotifyPushDisabled → onStreamingDown() →
      // startPolling(). If destroy() does not AWAIT that streaming shutdown
      // before finishing teardown, the newly (re)started poll timers survive
      // destroy() and keep firing fetches — against an http client that
      // destroy() has already closed.
      backend.stubSplitChanges(since: 1000);
      backend.stubAuth();
      backend.stubStreamingOpen();

      final config = _config(
        backend,
        featureFlagsPollingRate: 1,
        segmentsPollingRate: 1,
      );

      final periodicTimers = <Timer>[];
      final uncaught = <Object>[];

      await runZonedGuarded(
        () async {
          final factory = SplitFactory.create('fake-api-key', config);
          final client = factory.client();
          await client.whenReady().timeout(const Duration(seconds: 5));

          final pushUp =
              await _until(() => backend.streamingRequests.isNotEmpty);
          expect(pushUp, isTrue,
              reason: 'The SSE connection MUST open after the initial '
                  'fetch');
          // Give the fire-and-forget onPushEnabled callback a moment to
          // actually stop the poll timers before destroy() runs.
          await Future<void>.delayed(const Duration(milliseconds: 200));

          await factory.destroy();
          // featureFlagsPollingRate/segmentsPollingRate are 1s; wait several
          // multiples past destroy() so a restarted timer would have fired.
          await Future<void>.delayed(const Duration(seconds: 3));
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
      expect(active, isEmpty,
          reason: 'destroy() MUST await streaming shutdown before teardown '
              'completes, so a push-down callback firing during teardown '
              'cannot restart poll timers that outlive destroy()');
      expect(uncaught, isEmpty);
    });
  });
}
