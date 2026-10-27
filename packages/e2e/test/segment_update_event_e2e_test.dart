import 'dart:async';
import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// End-to-end coverage for BUG #12 (Node parity): `whenUpdated()` MUST also
/// fire — with an EMPTY payload (`[]`) — when segment (server-side) or
/// membership (client-side) data changes, not just when feature flags
/// change (spec §4.6, §8.2). Covers both sync drivers (polling, streaming)
/// on both SDK flavors:
///   (a) server-side polling /segmentChanges adds a key
///   (b) server-side streaming SEGMENT_UPDATE triggers an on-demand
///       /segmentChanges fetch that adds a key
///   (c) client-side polling /memberships/:key changes a key's membership
///   (d) client-side streaming MEMBERSHIPS_MS_UPDATE (SEGMENT_REMOVAL)
///       applied in place changes a key's membership
///
/// Before this fix, `SegmentChangesFetcher`/`MembershipsFetcher` only
/// reported readiness, never routed through `EventsManager.notifyUpdate` —
/// so `whenUpdated()` stayed silent on every segment/membership-only change.
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

/// A single flag whose rollout condition references the given [segmentName]
/// via an IN_SEGMENT matcher, so the server-side rule store registers that
/// segment after the initial /splitChanges fetch — without this, the
/// server-side segments poller has nothing registered to fetch at all.
Map<String, dynamic> _flagWithSegmentDef({
  required String name,
  required int changeNumber,
  required String segmentName,
}) =>
    {
      'trafficTypeName': 'user',
      'name': name,
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 2,
      'status': 'ACTIVE',
      'killed': false,
      'defaultTreatment': 'off',
      'changeNumber': changeNumber,
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
                'userDefinedSegmentMatcherData': {'segmentName': segmentName},
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
          'label': 'in segment $segmentName',
        }
      ],
      'configurations': <String, dynamic>{},
      'sets': <String>[],
    };

/// Builds a `/segmentChanges/:name` response body for the given cursor pair.
MockResponse _segResp({
  required String name,
  List<String> added = const [],
  List<String> removed = const [],
  required int since,
  required int till,
}) {
  return MockResponse()
      .setStatusCode(200)
      .setHeader('Content-Type', 'application/json')
      .setBody(jsonEncode({
        'name': name,
        'added': added,
        'removed': removed,
        'since': since,
        'till': till,
      }));
}

/// Builds a `/memberships/:key` response body with the given mySegments.
MockResponse _membershipsResp({
  List<String> ms = const [],
  List<String> ls = const [],
}) {
  return MockResponse()
      .setStatusCode(200)
      .setHeader('Content-Type', 'application/json')
      .setBody(jsonEncode({
        'ms': {'k': ms, 'cn': 1000},
        'ls': {'k': ls, 'cn': -1},
      }));
}

void main() {
  group('whenUpdated() on segment/membership changes (BUG #12)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        '(a) server-side polling: a /segmentChanges fetch that adds a key '
        'emits exactly one [] whenUpdated event', () async {
      backend.stubSplitChanges(
        since: 1000,
        splits: [
          _flagWithSegmentDef(
            name: 'flag_with_segment',
            changeNumber: 1000,
            segmentName: 'beta_users',
          )
        ],
      );
      backend.stubSegmentChangesHandler((req, callIndex) {
        if (callIndex == 0) {
          // Initial sync: segment registered via the flag parse above, but
          // not yet fetched. Respond already-caught-up (no diff) so READY
          // completes without an update firing yet.
          return _segResp(name: 'beta_users', since: -1, till: -1);
        }
        if (callIndex == 1) {
          // First post-READY poll: a genuine change.
          return _segResp(
              name: 'beta_users', added: ['user_a'], since: -1, till: 5);
        }
        // `fetchForSegment`'s own greedy loop issues one more confirming
        // call (since=5) before it reports caught-up — this MUST NOT cause
        // a second whenUpdated() emission for the same logical fetch.
        return _segResp(name: 'beta_users', since: 5, till: 5);
      });

      final baseUrl = _baseUrl(backend);
      final config = ss.SplitClientConfig(
        sync: ss.SyncConfig(
          serviceEndpoints: ss.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 30,
          streamingEnabled: false,
        ),
        installSignalHandler: false,
        logLevel: ss.LogLevel.warning,
      );

      final factory = ss.SplitFactory.create('fake-api-key', config);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      expect(
          await _until(() => backend.segmentChangesRequests.length >= 3,
              timeout: const Duration(seconds: 35)),
          isTrue,
          reason: 'The first post-READY poll cycle MUST run (callIndex 1) '
              'followed by the loop\'s own confirming call (callIndex 2)');

      expect(await _until(() => updates.isNotEmpty), isTrue,
          reason: 'whenUpdated() MUST emit when a polled /segmentChanges '
              'fetch adds a key, with an empty payload (spec §4.6/§8.2)');
      expect(updates, [[]],
          reason: 'Exactly one [] event — the loop\'s own extra confirming '
              'call MUST NOT cause a second emission for the same fetch');

      // Give any (buggy) duplicate/async emission a window to show up.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(updates, [[]]);

      await sub.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 45)));

    test(
        '(b) server-side streaming: a SEGMENT_UPDATE-triggered on-demand '
        'fetch that adds a key emits exactly one [] whenUpdated event',
        () async {
      // No flags registered, so the push-up catch-up aggregate fetch
      // (SegmentChangesFetcher.fetch(), which only loops registered
      // segments) never touches "seg_x" — every /segmentChanges/seg_x
      // request can only come from the SEGMENT_UPDATE-triggered coordinator,
      // ruling out a race with catch-up over the same segment name. (An
      // empty splits list also avoids the catch-up /splitChanges fetch
      // re-delivering a flag definition on every call — an unrelated,
      // pre-existing quirk of `stubSplitChanges` always echoing back its
      // fixed `splits` list — which would otherwise pollute `updates` with
      // an unrelated flag-change event.)
      backend.stubSplitChanges(since: 1000);
      backend.stubSegmentChangesHandler((req, callIndex) {
        final name = req.path.split('/').last;
        final noCache = req.headers['cache-control'] == 'no-cache';
        if (!noCache) {
          return _segResp(name: name, since: -1, till: -1);
        }
        return _segResp(name: name, added: ['member_key'], since: -1, till: 5);
      });
      backend.stubAuth();
      backend.stubStreaming(events: [
        MockBackend.segmentUpdateEvent(segmentName: 'seg_x', changeNumber: 5),
      ]);

      final baseUrl = _baseUrl(backend);
      final config = ss.SplitClientConfig(
        sync: ss.SyncConfig(
          serviceEndpoints: ss.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        installSignalHandler: false,
        logLevel: ss.LogLevel.warning,
      );

      final factory = ss.SplitFactory.create('fake-api-key', config);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');

      expect(await _until(() => updates.isNotEmpty), isTrue,
          reason: 'whenUpdated() MUST emit when a streaming-triggered '
              '/segmentChanges fetch adds a key, with an empty payload');
      expect(updates, [[]]);

      await sub.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        '(c) client-side polling: a /memberships/:key fetch that changes '
        "the key's membership emits exactly one [] whenUpdated event",
        () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMembershipsHandler((req, callIndex) {
        if (callIndex == 0) {
          // Initial sync: a non-empty but DISTINCT baseline (not the
          // all-empty response other tests default to), so the first
          // post-READY poll below is unambiguously a real, different
          // change rather than a no-op re-delivery of the same state.
          return _membershipsResp(ms: ['pre_ready_seg']);
        }
        // First post-READY poll: a genuine membership change.
        return _membershipsResp(ms: ['beta_users']);
      });

      final baseUrl = _baseUrl(backend);
      final config = cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 30,
          streamingEnabled: false,
        ),
        logLevel: cs.LogLevel.warning,
      );

      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));

      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      expect(
          await _until(() => backend.membershipsRequests.length >= 2,
              timeout: const Duration(seconds: 35)),
          isTrue,
          reason: 'The first post-READY memberships poll MUST run');

      expect(await _until(() => updates.isNotEmpty), isTrue,
          reason: 'whenUpdated() MUST emit when a polled /memberships '
              "fetch changes the key's membership set, with an empty "
              'payload (spec §4.6/§8.2)');
      expect(updates, [[]]);

      // The "an unchanged subsequent poll must not fire again" and
      // "nothing fires before READY" cases are covered by unit tests on
      // `MembershipsFetcher`/`InMemoryMembershipStore` and `EventsManager`
      // respectively — asserting them here would need a second ~30s poll
      // cycle (or an artificial pre-READY race), which is unnecessary cost
      // for behavior that is cleanly isolable at the unit level.

      await sub.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 40)));

    test(
        '(d) client-side streaming: an in-place MEMBERSHIPS_MS_UPDATE '
        "(SEGMENT_REMOVAL) that changes the key's membership emits exactly "
        'one [] whenUpdated event', () async {
      backend.stubSplitChanges(since: 1000);
      // Both the initial sync fetch (callIndex 0) and the push-up catch-up
      // fetch (callIndex 1, spec §11.3) see the identical pre-removal
      // state — the test waits for both to land (see below) before sending
      // the SSE removal, so there is no race between the catch-up fetch and
      // the in-place apply over the same key's membership set.
      backend.stubMembershipsHandler((req, callIndex) {
        return _membershipsResp(ms: ['beta_users']);
      });
      backend.stubAuth();
      final sseCtrl = backend.stubStreamingInteractive();

      final baseUrl = _baseUrl(backend);
      final config = cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
        ),
        logLevel: cs.LogLevel.warning,
      );

      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create('fake-api-key', config, key);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));

      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');

      expect(
          await _until(() => backend.membershipsRequests.length >= 2), isTrue,
          reason: 'Push-up MUST trigger a catch-up memberships fetch (spec '
              '§11.3) — waiting for it to land before sending the SSE '
              'removal below makes the ordering deterministic instead of '
              'racing the two async operations against each other');

      sseCtrl.add(MockBackend.membershipsSegmentRemovalEvent(
        changeNumber: 2,
        names: ['beta_users'],
      ));
      // mock_http_server/dart:io only flush buffered response bytes to the
      // socket when the stream completes (see stubStreamingHold's doc in
      // mock_backend.dart) — closing here is what actually pushes the event
      // over the wire; the SDK reconnects afterward, which is fine since the
      // assertion below only needs the one update to have landed first.
      unawaited(sseCtrl.close());

      expect(await _until(() => updates.isNotEmpty), isTrue,
          reason: 'whenUpdated() MUST emit when an in-place '
              'MEMBERSHIPS_MS_UPDATE SEGMENT_REMOVAL actually changes the '
              "key's membership set, with an empty payload");
      expect(updates, [[]]);

      await sub.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
