import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mock_http_server/mock_http_server.dart';
import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// End-to-end coverage for gzip/zlib-compressed streaming payloads (spec
/// §12.2/§12.3, design 2026-10-19-streaming-decompression-design.md §6.1).
///
/// A streaming notification with `c == 1` (gzip) or `c == 2` (zlib) MUST be
/// inflated and applied in place exactly like an uncompressed one, so:
///   - a `SPLIT_UPDATE` with `pcn == stored` applies without `/splitChanges`;
///   - a BOUNDED membership update fetches `/memberships/<key>` only for the
///     keys whose bit is set in the (compressed) bitmap;
///   - a KEY_LIST update adds/removes the key's segment without any
///     `/memberships` fetch;
///   - a payload that cannot be decoded falls back to a fetch and logs the
///     JS-parity WARNING.
///
/// Every flow connects an interactive SSE stream, waits for the push-up
/// catch-up fetches to settle, takes a request-count baseline, and only then
/// delivers the event, so any request counted after the baseline is caused by
/// the event itself.

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

/// Waits until the backend's `/splitChanges` and `/memberships` request
/// counts stop changing for [quiet], i.e. the push-up catch-up fetches
/// (spec §11.3) have landed. Bounded by [timeout].
Future<void> _settle(
  MockBackend backend, {
  Duration quiet = const Duration(milliseconds: 600),
  Duration timeout = const Duration(seconds: 10),
}) async {
  int total() =>
      backend.splitChangesRequests.length + backend.membershipsRequests.length;
  var last = total();
  var lastChange = DateTime.now();
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final now = total();
    if (now != last) {
      last = now;
      lastChange = DateTime.now();
    } else if (DateTime.now().difference(lastChange) >= quiet) {
      return;
    }
  }
}

/// Delivers [event] over the interactive SSE stream. mock_http_server only
/// flushes buffered response bytes when the stream completes (see
/// `stubStreamingHold` in mock_backend.dart), so closing is what actually
/// pushes the event over the wire.
void _deliver(StreamController<SseEvent> ctrl, SseEvent event) {
  ctrl.add(event);
  unawaited(ctrl.close());
}

/// Captures everything the SDK prints (the SDK logger writes via `print`).
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

String _gzipB64(Map<String, dynamic> json) =>
    base64.encode(gzip.encode(utf8.encode(jsonEncode(json))));

// ZLibCodec emits an RFC 1950 zlib stream by default, which is what `c: 2`
// means on the wire.
String _zlibB64(Map<String, dynamic> json) =>
    base64.encode(zlib.encode(utf8.encode(jsonEncode(json))));

/// A flag with no conditions: it always evaluates to [defaultTreatment].
Map<String, dynamic> _flagDef({
  required int changeNumber,
  required String defaultTreatment,
}) =>
    {
      'name': 'flag_a',
      'trafficTypeName': 'user',
      'killed': false,
      'defaultTreatment': defaultTreatment,
      'conditions': <Map<String, dynamic>>[],
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 1,
      'algo': 2,
      'changeNumber': changeNumber,
      'status': 'ACTIVE',
      'configurations': <String, dynamic>{},
      'sets': <String>[],
    };

/// A flag that returns `on` only for members of the `beta_users` segment.
Map<String, dynamic> _segmentFlagDef() => {
      ..._flagDef(changeNumber: 1000, defaultTreatment: 'off'),
      'name': 'flag_segment',
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
                'userDefinedSegmentMatcherData': {'segmentName': 'beta_users'},
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
          'label': 'in segment beta_users',
        }
      ],
    };

/// `/splitChanges` handler: the first call returns [flags] at `till: 1000`;
/// every later call (push-up catch-up, fallback fetch) reports no change, so
/// a flag can only change through an in-place apply.
MockResponse Function(RecordedRequest, int) _splitChangesAt1000(
  List<Map<String, dynamic>> flags,
) =>
    (req, callIndex) {
      final body = callIndex == 0
          ? {
              'ff': {'s': -1, 't': 1000, 'd': flags},
              'rbs': {'s': -1, 't': 1000, 'd': <Map<String, dynamic>>[]},
            }
          : {
              'ff': {'s': 1000, 't': 1000, 'd': <Map<String, dynamic>>[]},
              'rbs': {'s': 1000, 't': 1000, 'd': <Map<String, dynamic>>[]},
            };
      return MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode(body));
    };

cs.SplitClientConfig _csConfig(String baseUrl) => cs.SplitClientConfig(
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

ss.SplitClientConfig _ssConfig(String baseUrl) => ss.SplitClientConfig(
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

int _membershipsFor(MockBackend backend, String key) =>
    backend.membershipsRequests
        .where((r) => r.path.endsWith('/memberships/$key'))
        .length;

void main() {
  // Vectors copied verbatim from javascript-commons
  // src/sync/streaming/__tests__/dataMocks.ts.
  //
  // bitmaps[0] (c = 1, gzip): `trueUserKeys[0]` has its bit set and
  // `falseUserKeys[0]` does not (asserted by parseUtils.spec.ts).
  const bitmapGzip =
      'H4sIAAAAAAAA/2JABxzYeIxQLguYFIBLN8Bl4EABjc+EzOnAsA4QAAD//8YBvWeAAAAA';
  const keyInBitmap = '88f8b33b-f858-4aea-bea2-a5f066bab3ce';
  const keyNotInBitmap = '88f8b33b-f858-4aea-bea2-a5f066bab3c0';
  // keylists[0] (c = 1, gzip): `addedUserKeys` = key1, key2.
  const keyListGzip =
      'H4sIAAAAAAAA/wTAsRHDUAgD0F2ofwEIkPAqPhdZIW0uu/v97GPXHU004ULuMGrYR6XUbIjlXULPPse+dt1yhJibBODjrTmj3GJ4emduuDDP/w0AAP//18WLsl0AAAA=';
  // Spec Appendix A.3: a gzip stream that is not a valid bitmap payload.
  const malformedBitmap = 'H4sIAAAAAAAAg5EYy8MEMA20A+//5L7VQwAEAAA';

  group('Compressed streaming payloads (spec §12.2/§12.3)', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
      backend.stubAuth();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        '(1) client-side: a gzip SPLIT_UPDATE with pcn == stored applies in '
        'place with no /splitChanges fetch', () async {
      backend.stubSplitChangesHandler(_splitChangesAt1000(
          [_flagDef(changeNumber: 1000, defaultTreatment: 'off')]));
      backend.stubMemberships();
      final sse = backend.stubStreamingInteractive();

      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create(
          'fake-api-key', _csConfig(_baseUrl(backend)), key);
      addTearDown(factory.destroy);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));
      expect(client.getTreatment('flag_a'), 'off');

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');
      await _settle(backend);
      final baseline = backend.splitChangesRequests.length;
      // Subscribe only after the catch-up fetches settled so no earlier
      // update can satisfy the assertion below.
      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      _deliver(
        sse,
        MockBackend.splitUpdateCompressedEvent(
          changeNumber: 1001,
          pcn: 1000,
          c: 1,
          d: _gzipB64(_flagDef(changeNumber: 1001, defaultTreatment: 'on')),
        ),
      );

      expect(
          await _until(() => updates.any((u) => u.contains('flag_a'))), isTrue,
          reason: 'whenUpdated() MUST emit flag_a when a gzip SPLIT_UPDATE '
              'is applied in place (the /splitChanges stub never returns '
              'the new definition, so only an in-place apply can do it)');
      expect(client.getTreatment('flag_a'), 'on');
      expect(backend.splitChangesRequests.length, baseline,
          reason: 'An in-place apply MUST NOT issue a /splitChanges fetch');

      await sub.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        '(2) server-side: a zlib SPLIT_UPDATE with pcn == stored applies in '
        'place with no /splitChanges fetch', () async {
      backend.stubSplitChangesHandler(_splitChangesAt1000(
          [_flagDef(changeNumber: 1000, defaultTreatment: 'off')]));
      backend.stubSegmentChanges();
      final sse = backend.stubStreamingInteractive();

      final factory =
          ss.SplitFactory.create('fake-api-key', _ssConfig(_baseUrl(backend)));
      addTearDown(factory.destroy);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));
      expect(client.getTreatment('user_a', 'flag_a'), 'off');

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');
      await _settle(backend);
      final baseline = backend.splitChangesRequests.length;
      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      _deliver(
        sse,
        MockBackend.splitUpdateCompressedEvent(
          changeNumber: 1001,
          pcn: 1000,
          c: 2,
          d: _zlibB64(_flagDef(changeNumber: 1001, defaultTreatment: 'on')),
        ),
      );

      expect(
          await _until(() => updates.any((u) => u.contains('flag_a'))), isTrue,
          reason: 'whenUpdated() MUST emit flag_a when a zlib SPLIT_UPDATE '
              'is applied in place (the /splitChanges stub never returns '
              'the new definition, so only an in-place apply can do it)');
      expect(client.getTreatment('user_a', 'flag_a'), 'on');
      expect(backend.splitChangesRequests.length, baseline,
          reason: 'An in-place apply MUST NOT issue a /splitChanges fetch');

      await sub.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        '(3) client-side: a gzip BOUNDED bitmap fetches /memberships only '
        'for the key whose bit is set', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      final sse = backend.stubStreamingInteractive();

      final inKey = cs.Key(matchingKey: keyInBitmap);
      final factory = cs.SplitFactory.create(
          'fake-api-key', _csConfig(_baseUrl(backend)), inKey);
      addTearDown(factory.destroy);
      final inClient = factory.client(inKey);
      await inClient.whenReady().timeout(const Duration(seconds: 5));
      // Readiness is per client: the second client is not usable until its
      // own memberships have landed.
      final outClient = factory.client(keyNotInBitmap);
      await outClient.whenReady().timeout(const Duration(seconds: 5));

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');
      await _settle(backend);
      final inBaseline = _membershipsFor(backend, keyInBitmap);
      final outBaseline = _membershipsFor(backend, keyNotInBitmap);

      _deliver(
        sse,
        MockBackend.membershipsUpdateEvent(
          u: 1,
          changeNumber: 1001,
          c: 1,
          d: bitmapGzip,
          h: 0, // HashingAlgorithm.none: zero jitter, deterministic timing.
        ),
      );

      expect(
          await _until(
              () => _membershipsFor(backend, keyInBitmap) > inBaseline),
          isTrue,
          reason: 'The key whose bit is set MUST get a /memberships fetch');
      // Prove a negative: allow any (wrongly) triggered fetch for the other
      // key to land, bounded and short because h: 0 means no jitter.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(_membershipsFor(backend, keyInBitmap), inBaseline + 1,
          reason: 'Exactly one extra /memberships fetch for the targeted key');
      expect(_membershipsFor(backend, keyNotInBitmap), outBaseline,
          reason: 'A key whose bit is NOT set MUST NOT be fetched');

      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        '(4) client-side: a gzip KEY_LIST with the key in `a` adds the '
        'segment in place with no /memberships fetch', () async {
      backend.stubSplitChanges(since: 1000, splits: [_segmentFlagDef()]);
      backend.stubMemberships();
      final sse = backend.stubStreamingInteractive();

      final key = cs.Key(matchingKey: 'key1');
      final factory = cs.SplitFactory.create(
          'fake-api-key', _csConfig(_baseUrl(backend)), key);
      addTearDown(factory.destroy);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));
      expect(client.getTreatment('flag_segment'), 'off');

      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');
      await _settle(backend);
      final baseline = backend.membershipsRequests.length;
      final updates = <List<String>>[];
      final sub = client.whenUpdated().listen(updates.add);

      _deliver(
        sse,
        MockBackend.membershipsUpdateEvent(
          u: 2,
          changeNumber: 1001,
          c: 1,
          d: keyListGzip,
          n: ['beta_users'],
        ),
      );

      expect(await _until(() => updates.isNotEmpty), isTrue,
          reason: 'whenUpdated() MUST fire when a gzip KEY_LIST adds the '
              "client's key to a segment in place");
      // Bounded wait: a (wrongly) scheduled fetch is immediate for u: 2 but
      // still async, so give it time to reach the server before asserting.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(backend.membershipsRequests.length, baseline,
          reason: 'An in-place KEY_LIST apply MUST NOT fetch /memberships');
      expect(client.getTreatment('flag_segment'), 'on',
          reason: 'beta_users MUST have been added to the key in place');

      await sub.cancel();
      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        '(5) client-side: a malformed BOUNDED payload falls back to an '
        'unbounded /memberships fetch and logs a WARNING', () async {
      backend.stubSplitChanges(since: 1000);
      backend.stubMemberships();
      final sse = backend.stubStreamingInteractive();

      final lines = await _captureLog(() async {
        final key = cs.Key(matchingKey: 'user_a');
        final factory = cs.SplitFactory.create(
            'fake-api-key', _csConfig(_baseUrl(backend)), key);
        addTearDown(factory.destroy);
        final client = factory.client(key);
        await client.whenReady().timeout(const Duration(seconds: 5));
        expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
            reason: 'The SSE connection MUST open after the initial fetch');
        await _settle(backend);
        final baseline = backend.membershipsRequests.length;

        _deliver(
          sse,
          MockBackend.membershipsUpdateEvent(
            u: 1,
            changeNumber: 1001,
            c: 1,
            d: malformedBitmap,
            h: 0,
          ),
        );

        expect(
            await _until(() => backend.membershipsRequests.length > baseline),
            isTrue,
            reason: 'An undecodable BOUNDED payload MUST fall back to an '
                'unbounded /memberships fetch');
        await factory.destroy();
      });

      expect(
          lines.where((l) =>
              l.contains('[WARNING]') &&
              l.contains('Fetching Memberships due to an error processing '
                  'BoundedFetchRequest notification')),
          isNotEmpty,
          reason: 'A decode failure on a non-empty `d` MUST log the JS-parity '
              'WARNING. Captured: $lines');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        '(6) client-side: a SPLIT_UPDATE with an unknown compression '
        '(c: 3) falls back to a /splitChanges fetch', () async {
      backend.stubSplitChangesHandler(_splitChangesAt1000(
          [_flagDef(changeNumber: 1000, defaultTreatment: 'off')]));
      backend.stubMemberships();
      final sse = backend.stubStreamingInteractive();

      final key = cs.Key(matchingKey: 'user_a');
      final factory = cs.SplitFactory.create(
          'fake-api-key', _csConfig(_baseUrl(backend)), key);
      addTearDown(factory.destroy);
      final client = factory.client(key);
      await client.whenReady().timeout(const Duration(seconds: 5));
      expect(await _until(() => backend.streamingRequests.isNotEmpty), isTrue,
          reason: 'The SSE connection MUST open after the initial fetch');
      await _settle(backend);
      final baseline = backend.splitChangesRequests.length;

      _deliver(
        sse,
        MockBackend.splitUpdateCompressedEvent(
          changeNumber: 1001,
          pcn: 1000,
          c: 3,
          d: base64.encode(utf8.encode('{}')),
        ),
      );

      expect(await _until(() => backend.splitChangesRequests.length > baseline),
          isTrue,
          reason: 'An unknown compression byte MUST fall back to a '
              '/splitChanges fetch');

      await factory.destroy();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
