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

    test('whenTimeout completes when initial sync fails within readyTimeout', () async {
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

    test('whenUpdated emits changed flags when they change via streaming', () async {
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
          'ff': {'s': 1000, 't': 1001, 'd': [flagPayload]},
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
      expect(await _until(() => backend.splitChangesRequests.length > 1), isTrue,
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
      final splitChangesCountBeforeDestroy = backend.splitChangesRequests.length;
      expect(splitChangesCountBeforeDestroy, greaterThanOrEqualTo(1),
          reason: 'At least one initial sync /splitChanges should have fired');

      await factory.destroy();

      // After destroy completes, no new /splitChanges polls should fire.
      await Future.delayed(const Duration(milliseconds: 500));
      expect(backend.splitChangesRequests.length,
          equals(splitChangesCountBeforeDestroy),
          reason: 'No additional /splitChanges polls should fire after destroy');

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
  });
}
