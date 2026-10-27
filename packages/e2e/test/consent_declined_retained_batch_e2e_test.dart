import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Consent DECLINED must drop a recorder's *retained* retry batch too, not
/// just its live store (spec §7.2: "queued data MUST be dropped").
///
/// Each recorder's `BatchSubmitter` (spec §13.1) holds onto a batch that
/// failed with a transient status (`5xx`/`429`) so it can be retried once on
/// the recorder's next flush cycle. If consent transitions to DECLINED
/// between the failed attempt and that retry, the retained batch must be
/// dropped along with the live impressions/events stores — otherwise stale,
/// consent-declined user data still goes out on the wire on the next flush.
///
/// Scenario, driven only through the public API (`client.flush()`,
/// `factory.userConsent().setStatus(...)`):
///   1. Consent GRANTED (default) — record an impression/event.
///   2. First `flush()` — the recorder's POST gets a transient `500`, so the
///      batch is retained for retry (spec §13.1).
///   3. Consent set to DECLINED.
///   4. Second `flush()` — asserts NO further POST happens: the retained
///      batch must have been dropped, not resent.
String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

MockResponse _status(int code) => MockResponse().setStatusCode(code);

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

void main() {
  group('Consent DECLINED drops a retained retry batch (e2e, spec §7.2)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'impressions: a batch retained after a 500 is dropped, not resent, '
        'once consent is DECLINED', () async {
      backend.stubSplitChanges(splits: [_allKeysOnFlag('retry_flag')]);
      backend.stubMemberships();
      backend.stubImpressionsBulkHandler((_, __) => _status(500));

      final cfg = cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(
            sdkUrl: _baseUrl(backend),
            eventsUrl: _baseUrl(backend),
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
        ),
        impressionsMode: cs.ImpressionsMode.debug,
        logLevel: cs.LogLevel.warning,
      );
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      expect(client.getTreatment('retry_flag'), 'on');

      await client.flush();
      expect(backend.impressionRequests, hasLength(1),
          reason: 'first POST fails with 500 — batch retained for retry');

      factory.userConsent().setStatus(cs.ConsentStatus.declined);

      await client.flush();
      expect(backend.impressionRequests, hasLength(1),
          reason: 'retained batch must be dropped on DECLINED, not resent');

      await factory.destroy();
    });

    test(
        'events: a batch retained after a 500 is dropped, not resent, once '
        'consent is DECLINED', () async {
      backend.stubSplitChanges();
      backend.stubMemberships();
      backend.stubEventsHandler((_, __) => _status(500));

      final cfg = cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(
            sdkUrl: _baseUrl(backend),
            eventsUrl: _baseUrl(backend),
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          eventsPushRate: 9999,
        ),
        logLevel: cs.LogLevel.warning,
      );
      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', cfg, key);
      await factory.client(key).whenReady().timeout(const Duration(seconds: 5));
      final client = factory.client(key);

      expect(client.track('purchase', 'user', value: 1.0), isTrue);

      await client.flush();
      expect(backend.eventRequests, hasLength(1),
          reason: 'first POST fails with 500 — batch retained for retry');

      factory.userConsent().setStatus(cs.ConsentStatus.declined);

      await client.flush();
      expect(backend.eventRequests, hasLength(1),
          reason: 'retained batch must be dropped on DECLINED, not resent');

      await factory.destroy();
    });
  });
}
