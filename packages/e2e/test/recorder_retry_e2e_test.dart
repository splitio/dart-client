import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Recorder POST retry-on-failure (spec §13.1): a batch that fails with a
/// transient status (`429`/`5xx`) or a transport error MUST be retained and
/// retried once on the recorder's *next* flush cycle — observable here as a
/// second real HTTP POST, driven only through the public `client.flush()`
/// API, carrying the same items as the failed first POST. A second
/// consecutive failure MUST drop the batch (no third POST repeats it). A
/// non-retryable status (other `4xx`) MUST drop the batch immediately (no
/// retry at all).
///
/// Covers all four recorder types — impressions, events, impression counts,
/// unique keys — with impressions/events exercised on the client-side flavor
/// and counts/unique-keys exercised in NONE mode (also client-side, the
/// mode that activates both of those recorders). One server-side scenario
/// (events) confirms the shared `BatchSubmitter` behaves identically on the
/// other flavor.
///
/// A rollout condition on ALL_KEYS with a single 100%-sized "on" partition,
/// so every key evaluates to "on" deterministically regardless of hash seed.
Map<String, dynamic> _allKeysOnFlag(String name) => {
      'trafficTypeName': 'user',
      'name': name,
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 1,
      'status': 'ACTIVE',
      'killed': false,
      'defaultTreatment': 'off',
      'changeNumber': 1000,
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
            {'treatment': 'on', 'size': 100}
          ],
          'label': 'default rule',
        }
      ],
      'configurations': {},
      'sets': [],
    };

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

MockResponse _status(int code) => MockResponse().setStatusCode(code);

void main() {
  group('Client-side impressions recorder retry (e2e, spec §13.1)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    cs.SplitClientConfig config(String baseUrl) => cs.SplitClientConfig(
          sync: cs.SyncConfig(
            serviceEndpoints: cs.ServiceEndpoints(
              sdkUrl: baseUrl,
              eventsUrl: baseUrl,
            ),
            featureFlagsPollingRate: 9999,
            segmentsPollingRate: 9999,
            impressionsPushRate: 9999,
          ),
          impressionsMode: cs.ImpressionsMode.debug,
          logLevel: cs.LogLevel.warning,
        );

    test(
        '500 then 200: the retained batch is resent on the next flush and '
        'carries the same impression', () async {
      backend.stubSplitChanges(splits: [_allKeysOnFlag('retry_flag')]);
      backend.stubMemberships();

      final cfg = config(_baseUrl(backend));
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      backend.stubImpressionsBulkHandler(
          (_, i) => i == 0 ? _status(500) : _status(200));

      expect(client.getTreatment('retry_flag'), 'on');

      await client.flush();
      expect(backend.impressionRequests, hasLength(1),
          reason: 'first POST fails with 500');

      await client.flush();
      expect(backend.impressionRequests, hasLength(2),
          reason: 'retained batch resent on next flush cycle');

      final first =
          jsonDecode(utf8.decode(backend.impressionRequests[0].body)) as List;
      final second =
          jsonDecode(utf8.decode(backend.impressionRequests[1].body)) as List;
      expect(second, equals(first),
          reason: 'retry carries the exact same batch as the failed POST');
      expect((second.first['i'] as List).first['k'], 'user_a');

      await factory.destroy();
    });

    test('500 twice: the batch is dropped — a third flush posts nothing new',
        () async {
      backend.stubSplitChanges(splits: [_allKeysOnFlag('retry_flag')]);
      backend.stubMemberships();

      final cfg = config(_baseUrl(backend));
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      backend.stubImpressionsBulkHandler((_, __) => _status(500));

      expect(client.getTreatment('retry_flag'), 'on');

      await client.flush();
      await client.flush();
      expect(backend.impressionRequests, hasLength(2),
          reason: 'first POST + one retry, both failing');

      await client.flush();
      expect(backend.impressionRequests, hasLength(2),
          reason: 'dropped after the retry failed — no third POST');

      await factory.destroy();
    });

    test('400: the batch is dropped immediately — no retry on next flush',
        () async {
      backend.stubSplitChanges(splits: [_allKeysOnFlag('retry_flag')]);
      backend.stubMemberships();

      final cfg = config(_baseUrl(backend));
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      backend.stubImpressionsBulkHandler((_, __) => _status(400));

      expect(client.getTreatment('retry_flag'), 'on');

      await client.flush();
      expect(backend.impressionRequests, hasLength(1));

      await client.flush();
      expect(backend.impressionRequests, hasLength(1),
          reason: 'non-retryable status — nothing retained');

      await factory.destroy();
    });
  });

  group('Client-side events recorder retry (e2e, spec §13.1)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    cs.SplitClientConfig config(String baseUrl) => cs.SplitClientConfig(
          sync: cs.SyncConfig(
            serviceEndpoints: cs.ServiceEndpoints(
              sdkUrl: baseUrl,
              eventsUrl: baseUrl,
            ),
            featureFlagsPollingRate: 9999,
            segmentsPollingRate: 9999,
            eventsPushRate: 9999,
          ),
          logLevel: cs.LogLevel.warning,
        );

    test(
        '500 then 200: the retained batch is resent on the next flush and '
        'carries the same event', () async {
      backend.stubSplitChanges();
      backend.stubMemberships();

      final cfg = config(_baseUrl(backend));
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      backend.stubEventsHandler((_, i) => i == 0 ? _status(500) : _status(200));

      expect(client.track('purchase', 'user', value: 1.0), isTrue);

      await client.flush();
      expect(backend.eventRequests, hasLength(1));

      await client.flush();
      expect(backend.eventRequests, hasLength(2));

      final first =
          jsonDecode(utf8.decode(backend.eventRequests[0].body)) as List;
      final second =
          jsonDecode(utf8.decode(backend.eventRequests[1].body)) as List;
      expect(second, equals(first));
      expect(second.first['eventTypeId'], 'purchase');

      await factory.destroy();
    });

    test('500 twice: the batch is dropped — a third flush posts nothing new',
        () async {
      backend.stubSplitChanges();
      backend.stubMemberships();

      final cfg = config(_baseUrl(backend));
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      backend.stubEventsHandler((_, __) => _status(500));
      client.track('purchase', 'user', value: 1.0);

      await client.flush();
      await client.flush();
      expect(backend.eventRequests, hasLength(2));

      await client.flush();
      expect(backend.eventRequests, hasLength(2),
          reason: 'dropped after the retry failed — no third POST');

      await factory.destroy();
    });

    test('400: the batch is dropped immediately — no retry on next flush',
        () async {
      backend.stubSplitChanges();
      backend.stubMemberships();

      final cfg = config(_baseUrl(backend));
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      backend.stubEventsHandler((_, __) => _status(422));
      client.track('purchase', 'user', value: 1.0);

      await client.flush();
      expect(backend.eventRequests, hasLength(1));

      await client.flush();
      expect(backend.eventRequests, hasLength(1),
          reason: 'non-retryable status — nothing retained');

      await factory.destroy();
    });
  });

  group(
      'Client-side impression counts / unique keys retry (e2e, NONE mode, '
      'spec §13.1)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    cs.SplitClientConfig config(String baseUrl) => cs.SplitClientConfig(
          sync: cs.SyncConfig(
            serviceEndpoints: cs.ServiceEndpoints(
              sdkUrl: baseUrl,
              eventsUrl: baseUrl,
              telemetryUrl: baseUrl,
            ),
            featureFlagsPollingRate: 9999,
            segmentsPollingRate: 9999,
            impressionsPushRate: 9999,
          ),
          impressionsMode: cs.ImpressionsMode.none,
          logLevel: cs.LogLevel.warning,
        );

    test(
        'impression counts: 500 then 200 — the retained batch is resent on '
        'the next flush', () async {
      backend.stubSplitChanges(splits: [_allKeysOnFlag('retry_flag')]);
      backend.stubMemberships();
      backend.stubUniqueKeysHandler((_, __) => _status(200));

      final cfg = config(_baseUrl(backend));
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      backend.stubImpressionsCountHandler(
          (_, i) => i == 0 ? _status(500) : _status(200));

      client.getTreatment('retry_flag');
      client.getTreatment('retry_flag');

      await client.flush();
      expect(backend.impressionsCountRequests, hasLength(1));

      await client.flush();
      expect(backend.impressionsCountRequests, hasLength(2));

      final first =
          jsonDecode(utf8.decode(backend.impressionsCountRequests[0].body))
              as Map;
      final second =
          jsonDecode(utf8.decode(backend.impressionsCountRequests[1].body))
              as Map;
      expect(second, equals(first));
      final pf = (second['pf'] as List).cast<Map<String, dynamic>>();
      expect(pf.first['f'], 'retry_flag');
      expect(pf.first['rc'], 2);

      await factory.destroy();
    });

    test(
        'unique keys: 500 then 200 — the retained batch is resent on the '
        'next flush', () async {
      backend.stubSplitChanges(splits: [_allKeysOnFlag('retry_flag')]);
      backend.stubMemberships();
      backend.stubImpressionsCountHandler((_, __) => _status(200));

      final cfg = config(_baseUrl(backend));
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      backend.stubUniqueKeysHandler(
          (_, i) => i == 0 ? _status(500) : _status(200));

      client.getTreatment('retry_flag');

      await client.flush();
      expect(backend.uniqueKeysRequests, hasLength(1));

      await client.flush();
      expect(backend.uniqueKeysRequests, hasLength(2));

      final first =
          jsonDecode(utf8.decode(backend.uniqueKeysRequests[0].body)) as Map;
      final second =
          jsonDecode(utf8.decode(backend.uniqueKeysRequests[1].body)) as Map;
      expect(second, equals(first));
      final keys = (second['keys'] as List).cast<Map<String, dynamic>>();
      expect(keys.first['k'], 'user_a');

      await factory.destroy();
    });
  });

  group('Server-side events recorder retry (e2e, spec §13.1 — other flavor)',
      () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        '500 then 200: the retained batch is resent on the next flush and '
        'carries the same event', () async {
      backend.stubSplitChanges();

      final baseUrl = _baseUrl(backend);
      final cfg = ss.SplitClientConfig(
        sync: ss.SyncConfig(
          serviceEndpoints: ss.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          eventsPushRate: 9999,
          streamingEnabled: false,
        ),
        installSignalHandler: false,
        logLevel: ss.LogLevel.warning,
      );

      final factory = ss.SplitFactory.create('fake-api-key', cfg);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      backend.stubEventsHandler((_, i) => i == 0 ? _status(500) : _status(200));

      expect(client.track('user_a', 'user', 'purchase', value: 1.0), isTrue);

      await client.flush();
      expect(backend.eventRequests, hasLength(1));

      await client.flush();
      expect(backend.eventRequests, hasLength(2));

      final first =
          jsonDecode(utf8.decode(backend.eventRequests[0].body)) as List;
      final second =
          jsonDecode(utf8.decode(backend.eventRequests[1].body)) as List;
      expect(second, equals(first));
      expect(second.first['eventTypeId'], 'purchase');
      expect(second.first['key'], 'user_a');

      await factory.destroy();
    });
  });
}
