import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Regression guard for a review finding on `FlagsSegmentSync.onFlagsChanged`
/// (added alongside the fix in commit c9a3979):
///
/// `SyncManager.initialSync()` (-> `PollingManagerSS.syncAll()`) runs flags
/// first, then segments:
/// `await _flagsTask.fetch()` (= `FlagsFetcher.fetch`) THEN
/// `await _segmentsTask.fetch()` (= `SegmentChangesFetcher.fetch`, all
/// registered segments). But `FlagsFetcher.fetch()` calls its `onUpdate`
/// callback SYNCHRONOUSLY, before it returns — and that callback is wired
/// (in `ServerDependencyContainer`) to `FlagsSegmentSync.onFlagsChanged()`,
/// which — when the flags fetch just registered a brand-new segment — fires
/// `unawaited(segmentChangesFetcher.fetch())` *immediately*, i.e. strictly
/// BEFORE `initialSync()` even reaches its own `await _segmentsTask.fetch()`
/// line. Both calls target the exact same shared `SegmentChangesFetcher`
/// instance and therefore race to fetch the SAME, just-registered segment
/// at the SAME `since=-1` cursor:
///   (a) one extra, duplicate `GET /segmentChanges/{name}?since=-1` at
///       startup, and
///   (b) because `InMemorySegmentStore.update()` reports `changed` from the
///       response payload's added/removed lists — not from whether the
///       store's set actually mutated — the unawaited duplicate call, if it
///       resolves AFTER `_segmentsTask.fetch()`'s own call let READY fire,
///       re-reports `changed: true` for data that was already applied,
///       firing a spurious post-READY `whenUpdated()` even though nothing
///       changed on the backend between the two calls.
/// Also covers destroy(): once destroy() completes, `onFlagsChanged` MUST
/// NOT be able to start a brand-new fetch.
String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

/// Polls [condition] until it is true or [timeout] elapses. Call sites MUST
/// assert on the returned value so a genuinely-unmet condition FAILS the
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

/// A single flag whose rollout condition references `dart_qa_beta` via an
/// IN_SEGMENT matcher, so the first `/splitChanges` fetch registers a
/// brand-new segment the store has never fetched before — the exact
/// condition `FlagsSegmentSync.onFlagsChanged` reacts to.
Map<String, dynamic> get _flagWithSegment => {
      'trafficTypeName': 'user',
      'name': 'flag_with_segment',
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 2,
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
                'matcherType': 'IN_SEGMENT',
                'negate': false,
                'userDefinedSegmentMatcherData': {
                  'segmentName': 'dart_qa_beta',
                },
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
          'label': 'in segment dart_qa_beta',
        }
      ],
      'configurations': <String, dynamic>{},
      'sets': <String>[],
    };

SplitClientConfig _config(MockBackend backend) {
  final baseUrl = _baseUrl(backend);
  return SplitClientConfig(
    sync: SyncConfig(
      serviceEndpoints: ServiceEndpoints(
        sdkUrl: baseUrl,
        eventsUrl: baseUrl,
        authUrl: baseUrl,
        streamingUrl: baseUrl,
      ),
      // Floored to 30s by SyncConfig.normalized() regardless — kept high to
      // document intent: this test's short observation window MUST NOT
      // overlap a real periodic poll tick, so every observed request is
      // attributable to startup, not a later poll cycle.
      featureFlagsPollingRate: 9999,
      segmentsPollingRate: 9999,
      // Streaming disabled: the race under test is purely between
      // SyncManager.initialSync()'s own segments fetch and
      // FlagsSegmentSync's immediate trigger — streaming's catch-up path is
      // a separate concern and would only add noise here.
      streamingEnabled: false,
    ),
    installSignalHandler: false,
    logLevel: LogLevel.warning,
  );
}

void main() {
  group('Server-side segment fetch dedupe on startup (review finding)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'fetches a newly-referenced segment exactly once at since=-1, emits '
        'no whenUpdated once nothing further changes, and makes no HTTP '
        'after destroy() completes', () async {
      backend.stubSplitChangesHandler((_, __) {
        final body = jsonEncode({
          'ff': {
            's': -1,
            't': 1000,
            'd': [_flagWithSegment],
          },
          'rbs': {'s': -1, 't': 1000, 'd': []},
        });
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(body);
      });

      // Backend state is keyed by the request's own `since` cursor, not by
      // call order — deliberately, so the assertions below hold regardless
      // of which of the two racing requests (the legitimate one, or the
      // buggy duplicate) the mock server happens to see first.
      // since=-1 (first-ever fetch): one real change (adds 'member_key').
      // since=2000 (the follow-up confirming call every fetchForSegment loop
      // makes once caught up, and any later/duplicate call at the same
      // cursor): stable — no further change, ever.
      backend.stubSegmentChangesHandler((req, callIndex) {
        final since = req.queryParameters['since'];
        if (since == '-1') {
          return MockResponse()
              .setStatusCode(200)
              .setHeader('Content-Type', 'application/json')
              .setBody(jsonEncode({
                'name': 'dart_qa_beta',
                'added': ['member_key'],
                'removed': <String>[],
                'since': -1,
                'till': 2000,
              }));
        }
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(jsonEncode({
              'name': 'dart_qa_beta',
              'added': <String>[],
              'removed': <String>[],
              'since': 2000,
              'till': 2000,
            }));
      });

      final factory = SplitFactory.create('fake-api-key', _config(backend));
      final client = factory.client();

      await expectLater(
          client.whenReady().timeout(const Duration(seconds: 5)), completes);

      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      // Give every in-flight request — including a buggy duplicate and its
      // own confirming since=2000 follow-up — time to fully land before
      // asserting. On fixed code this settles at exactly 2 requests
      // (since=-1 then since=2000); on buggy code it settles at 4 (each of
      // the two racing fetchForSegment calls makes its own pair).
      expect(
          await _until(() => backend.segmentChangesRequests.length >= 2,
              timeout: const Duration(seconds: 5)),
          isTrue,
          reason: 'The initial segment fetch (since=-1) and its own '
              'confirming follow-up (since=2000) MUST both land');
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // (a) exactly one GET /segmentChanges/dart_qa_beta?since=-1 at startup.
      final sinceMinus1Requests = backend.segmentChangesRequests
          .where((r) => r.queryParameters['since'] == '-1')
          .toList();
      expect(sinceMinus1Requests, hasLength(1),
          reason: 'FlagsSegmentSync.onFlagsChanged() fires its own immediate '
              'segments fetch WITHOUT checking whether '
              'ServerSyncManager.initialSync() already has one running for '
              'the exact same newly-registered segment, so a buggy '
              'implementation sends this request twice.');

      // (b) no whenUpdated after READY — the backend never changes again.
      expect(updates, isEmpty,
          reason: 'The one real backend change (adding member_key) happens '
              'during initial sync, before READY, and MUST be dropped by '
              'EventsManager.notifyUpdate (pre-READY). A buggy duplicate '
              'fetch that resolves AFTER READY re-reports "changed" for '
              'data already applied — SegmentStore.update() derives '
              '"changed" from the response payload, not from whether the '
              'store actually mutated — producing a spurious post-READY '
              'whenUpdated with no corresponding backend change.');

      await sub.cancel();

      // (c) no HTTP of any kind once destroy() has completed. splitChanges
      // and segmentChanges are the only two endpoints this SDK can reach in
      // this config (streaming disabled, no track()/getTreatment() calls to
      // feed the impressions/events recorders), so their combined count is
      // a complete request tally.
      final beforeDestroy = backend.splitChangesRequests.length +
          backend.segmentChangesRequests.length;
      await factory.destroy();
      await Future<void>.delayed(const Duration(seconds: 1));
      final afterDestroy = backend.splitChangesRequests.length +
          backend.segmentChangesRequests.length;
      expect(afterDestroy, equals(beforeDestroy),
          reason: 'FlagsSegmentSync.onFlagsChanged() MUST return early once '
              'the factory is destroyed — no HTTP request may originate '
              'from it (or from anything else) after destroy() completes');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
