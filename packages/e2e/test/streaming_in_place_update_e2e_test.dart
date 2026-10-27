import 'dart:convert';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// End-to-end coverage for spec §12.1's in-place apply contract: when a
/// streaming `SPLIT_UPDATE` carries its definition inline (base64 `d`,
/// uncompressed `c == 0`) and applies without a `/splitChanges` fetch, the
/// SDK MUST still:
///   - emit `UPDATE` (`whenUpdated()` / SDK_UPDATE) with the affected flag
///     name(s), on both client-side and server-side;
///   - perform the same post-apply side effects as a fetched change, in
///     particular registering (and, on server-side, actually fetching) any
///     segment newly referenced by the in-place definition.
/// `SPLIT_KILL` applied in place MUST also emit the update event.
///
/// Before this fix, `FlagUpdateStrategy` mutated the rule store directly,
/// bypassing the `onUpdate` callback that both `whenUpdated()` and
/// server-side segment registration are wired through — so none of this
/// happened until an unrelated fetch happened to run.
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

/// A minimal valid flag definition with no conditions — sufficient for
/// `whenUpdated()` emission tests, which don't assert on evaluation.
Map<String, dynamic> _plainFlagDef({
  required String name,
  required int changeNumber,
  String status = 'ACTIVE',
  bool killed = false,
  String defaultTreatment = 'off',
}) =>
    {
      'name': name,
      'trafficTypeName': 'user',
      'killed': killed,
      'defaultTreatment': defaultTreatment,
      'conditions': <Map<String, dynamic>>[],
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 1,
      'algo': 2,
      'changeNumber': changeNumber,
      'status': status,
      'configurations': <String, dynamic>{},
      'sets': <String>[],
    };

/// A flag definition whose single rollout condition matches 100% of keys
/// via an `IN_SEGMENT` matcher on [segmentName] — used to assert that an
/// in-place apply registers (and, server-side, actually fetches) a
/// previously-unknown segment.
Map<String, dynamic> _flagWithSegmentDef({
  required String name,
  required int changeNumber,
  required String segmentName,
}) =>
    {
      'name': name,
      'trafficTypeName': 'user',
      'killed': false,
      'defaultTreatment': 'off',
      'changeNumber': changeNumber,
      'algo': 2,
      'seed': 2,
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'status': 'ACTIVE',
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

void main() {
  group('Streaming in-place apply side effects (spec §12.1)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test('client-side whenUpdated() fires on an in-place SPLIT_UPDATE',
        () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      backend.stubAuth();
      backend.stubStreaming(events: [
        MockBackend.splitUpdateInPlaceEvent(
          changeNumber: 1001,
          pcn: 1000,
          definition: _plainFlagDef(name: 'flag_a', changeNumber: 1001),
        ),
      ]);

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
          await _until(() => updates.isNotEmpty,
              timeout: const Duration(seconds: 5)),
          isTrue,
          reason: 'whenUpdated() MUST emit when an in-place SPLIT_UPDATE is '
              'applied, even though it never triggers a /splitChanges fetch');
      expect(updates.first, contains('flag_a'));

      // Every push-up edge — including the very first connect — also issues
      // its own catch-up /splitChanges fetch (spec §11.3), independent of
      // this bug. That stub's `splits` defaults to empty, so it never
      // returns `flag_a` — the update firing with `flag_a` can only have
      // come from the in-place apply, not from the unrelated catch-up
      // fetch's own (already-correct) onUpdate path.

      await sub.cancel();
      await factory.destroy();
    });

    test('server-side whenUpdated() fires on an in-place SPLIT_UPDATE',
        () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubSegmentChanges();
      backend.stubAuth();
      backend.stubStreaming(events: [
        MockBackend.splitUpdateInPlaceEvent(
          changeNumber: 1001,
          pcn: 1000,
          definition: _plainFlagDef(name: 'flag_a', changeNumber: 1001),
        ),
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

      expect(
          await _until(() => updates.isNotEmpty,
              timeout: const Duration(seconds: 5)),
          isTrue,
          reason: 'whenUpdated() MUST emit when an in-place SPLIT_UPDATE is '
              'applied on server-side, even though it never triggers a '
              '/splitChanges fetch');
      expect(updates.first, contains('flag_a'));

      // As above: the catch-up fetch that every push-up edge triggers
      // (spec §11.3) never returns `flag_a` (empty `splits` stub), so this
      // can only be the in-place apply's own onUpdate firing.

      await sub.cancel();
      await factory.destroy();
    });

    test(
        'server-side in-place SPLIT_UPDATE referencing a NEW segment '
        'fetches it and getTreatment evaluates IN_SEGMENT correctly', () async {
      // No flags initially, so `beta_users` is unknown to the segment store.
      backend.stubSplitChanges(since: 1000);
      backend.stubSegmentChangesHandler((req, callIndex) {
        final name = req.path.split('/').last;
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(jsonEncodeSegment(name));
      });
      backend.stubAuth();
      backend.stubStreaming(events: [
        MockBackend.splitUpdateInPlaceEvent(
          changeNumber: 1001,
          pcn: 1000,
          definition: _flagWithSegmentDef(
            name: 'flag_with_segment',
            changeNumber: 1001,
            segmentName: 'beta_users',
          ),
        ),
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

      final segmentChangesBaseline = backend.segmentChangesRequests.length;

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');

      expect(
          await _until(
              () =>
                  backend.segmentChangesRequests.length >
                  segmentChangesBaseline,
              timeout: const Duration(seconds: 5)),
          isTrue,
          reason: 'The in-place SPLIT_UPDATE references a brand-new segment '
              '("beta_users") that MUST be registered AND actively fetched '
              'via GET /segmentChanges — not just registered and left stale '
              'until an unrelated sync');

      expect(
          await _until(
              () =>
                  client.getTreatment('member_key', 'flag_with_segment') ==
                  'on',
              timeout: const Duration(seconds: 5)),
          isTrue,
          reason: 'Once /segmentChanges/beta_users has been fetched, '
              'getTreatment MUST evaluate the IN_SEGMENT rule against real '
              'membership data, not an empty segment');

      await factory.destroy();
    });

    test('client-side whenUpdated() fires on an in-place SPLIT_KILL', () async {
      // The follow-up fetch that always trails a SPLIT_KILL (spec §12.1)
      // MUST NOT be the thing that makes this test pass: callIndex 1+
      // reports no further changes (`t` already equal to the post-kill
      // change number, empty `d`), so if whenUpdated() emits, it can only be
      // from the in-place kill apply itself, not from the trailing fetch's
      // own (already-correct) onUpdate path.
      backend.stubSplitChangesHandler((req, callIndex) {
        final body = callIndex == 0
            ? {
                'ff': {
                  's': -1,
                  't': 1000,
                  'd': [_plainFlagDef(name: 'flag_a', changeNumber: 1000)],
                },
                'rbs': {'s': -1, 't': 1000, 'd': <Map<String, dynamic>>[]},
              }
            : {
                'ff': {'s': 1001, 't': 1001, 'd': <Map<String, dynamic>>[]},
                'rbs': {'s': 1000, 't': 1000, 'd': <Map<String, dynamic>>[]},
              };
        return MockResponse()
            .setStatusCode(200)
            .setHeader('Content-Type', 'application/json')
            .setBody(jsonEncode(body));
      });
      backend.stubMemberships();
      backend.stubAuth();
      backend.stubStreaming(events: [
        MockBackend.splitKillEvent(
          changeNumber: 1001,
          splitName: 'flag_a',
          defaultTreatment: 'on',
        ),
      ]);

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
          await _until(() => updates.isNotEmpty,
              timeout: const Duration(seconds: 5)),
          isTrue,
          reason: 'whenUpdated() MUST emit immediately when a SPLIT_KILL is '
              'applied in place, independent of the fetch that always '
              'follows a kill');
      expect(updates.first, contains('flag_a'));

      await sub.cancel();
      await factory.destroy();
    });
  });
}

/// Builds a `/segmentChanges/<name>` response that always includes
/// `member_key` as a member, caught up immediately (`since == till`).
String jsonEncodeSegment(String name) => '''
{
  "name": "$name",
  "added": ["member_key"],
  "removed": [],
  "since": -1,
  "till": -1
}
''';
