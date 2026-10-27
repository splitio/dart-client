import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mock_http_server/mock_http_server.dart';

/// Internal test helper for mocking Split backend interactions.
///
/// [MockBackend] wraps [MockWebServer] with [RouteDispatcher] to enable
/// route-based response stubbing, allowing tests with multiple mocked endpoints
/// to avoid FIFO queue ordering dependencies.
///
/// Usage:
/// ```dart
/// final backend = MockBackend();
/// await backend.start();
/// backend.stubSplitChanges();
/// // Make HTTP requests to backend.url
/// await backend.shutdown();
/// ```
class MockBackend {
  final _server = MockWebServer();
  final _dispatcher = RouteDispatcher();

  /// Captured requests to /splitChanges for assertions.
  final List<RecordedRequest> splitChangesRequests = [];

  /// Captured requests to /sse or /event-stream for assertions.
  final List<RecordedRequest> streamingRequests = [];

  /// Captured GET requests to /v2/auth for assertions.
  final List<RecordedRequest> authRequests = [];

  /// Captured POST requests to /impressions for assertions.
  final List<RecordedRequest> impressionRequests = [];

  /// Captured POST requests to /events/bulk for assertions.
  final List<RecordedRequest> eventRequests = [];

  /// Captured POST requests to /testImpressions/count for assertions. Kept
  /// separate from [impressionRequests] because its body shape is a Map
  /// (`{"pf": [...]}`), not a List, so it is not compatible with the
  /// [postedImpressions]/[postedImpressionsFlat] getters.
  final List<RecordedRequest> impressionsCountRequests = [];

  /// Captured POST requests to /v1/keys/cs (client-side MTK) for assertions.
  final List<RecordedRequest> uniqueKeysRequests = [];

  /// Captured POST requests to /v1/keys/ss (server-side MTK) for assertions.
  final List<RecordedRequest> uniqueKeysSsRequests = [];

  /// Captured GET requests to /segmentChanges/:name for assertions.
  final List<RecordedRequest> segmentChangesRequests = [];

  /// Captured GET requests to /memberships/:key for assertions.
  final List<RecordedRequest> membershipsRequests = [];

  /// Long-lived SSE stream controllers held open by [stubStreamingOpen], closed
  /// on [shutdown] so the process does not hang.
  final List<StreamController<SseEvent>> _openStreams = [];

  /// Start the mock server and register the dispatcher.
  Future<void> start() async {
    _server.dispatcher = _dispatcher;
    await _server.start();
  }

  /// Stop the mock server and clean up resources.
  Future<void> shutdown() async {
    for (final ctrl in _openStreams) {
      if (!ctrl.isClosed) await ctrl.close();
    }
    _openStreams.clear();
    await _server.shutdown();
  }

  /// Base URL of the running mock server.
  String get url => _server.url;

  /// Returns all posted impressions in the raw grouped-by-feature format:
  /// `[{"f": "feature", "i": [{"k":..,"t":..,"m":..,"c":..,"r":..,?b,?pt}]}]`
  List<Map<String, dynamic>> get postedImpressions {
    final List<Map<String, dynamic>> all = [];
    for (final req
        in impressionRequests.where((r) => r.path.endsWith('/bulk'))) {
      final body = jsonDecode(utf8.decode(req.body)) as List;
      for (final group in body) {
        all.add(Map<String, dynamic>.from(group as Map));
      }
    }
    return all;
  }

  /// Returns all posted impressions as a flat list of individual impression
  /// entries with their feature name attached:
  /// `[{"f": "feature", "k":..., "t":..., "m":..., "c":..., "r":..., ?b, ?pt}]`
  List<Map<String, dynamic>> get postedImpressionsFlat {
    final List<Map<String, dynamic>> flat = [];
    for (final group in postedImpressions) {
      final feature = group['f'] as String;
      final items = group['i'] as List;
      for (final imp in items) {
        flat.add(<String, dynamic>{
          'f': feature,
          ...Map<String, dynamic>.from(imp as Map),
        });
      }
    }
    return flat;
  }

  /// Register a route handler for GET /splitChanges requests.
  /// Captures each request for later assertions.
  void stubSplitChanges({
    List<Map<String, dynamic>> splits = const [],
    int since = -1,
  }) {
    _dispatcher.get(RegExp(r'/splitChanges'), (req) {
      splitChangesRequests.add(req);
      return _splitChangesResponse(splits: splits, since: since);
    });
  }

  /// Register a custom per-request handler for GET /splitChanges.
  /// The [handler] receives the request and the 0-based call index, allowing
  /// tests to return different responses on subsequent fetches (e.g. return
  /// new flag data on the re-sync triggered by a SPLIT_UPDATE notification).
  void stubSplitChangesHandler(
    MockResponse Function(RecordedRequest req, int callIndex) handler,
  ) {
    int callIndex = 0;
    _dispatcher.get(RegExp(r'/splitChanges'), (req) {
      splitChangesRequests.add(req);
      return handler(req, callIndex++);
    });
  }

  /// Register a route handler for POST /events/bulk requests.
  /// Captures each request into [eventRequests] and returns 200.
  void stubEvents() {
    _dispatcher.post(RegExp(r'/events/bulk'), (req) {
      eventRequests.add(req);
      return MockResponse().setStatusCode(200);
    });
  }

  /// Register a custom per-request handler for POST /events/bulk. The
  /// [handler] receives the request and a 0-based call index (one per POST
  /// actually sent), letting a test return a transient failure on an early
  /// call and a success later — used to exercise recorder retry-on-failure
  /// behavior (spec §13.1).
  void stubEventsHandler(
    MockResponse Function(RecordedRequest req, int callIndex) handler,
  ) {
    int callIndex = 0;
    _dispatcher.post(RegExp(r'/events/bulk'), (req) {
      eventRequests.add(req);
      return handler(req, callIndex++);
    });
  }

  /// Register a custom per-request handler for POST /testImpressions/bulk
  /// (individual impressions). See [stubEventsHandler] for the call-index
  /// contract.
  void stubImpressionsBulkHandler(
    MockResponse Function(RecordedRequest req, int callIndex) handler,
  ) {
    int callIndex = 0;
    _dispatcher.post(RegExp(r'/testImpressions'), (req) {
      impressionRequests.add(req);
      return handler(req, callIndex++);
    });
  }

  /// Register a custom per-request handler for POST /testImpressions/count
  /// (impression counts, OPTIMIZED/NONE modes). See [stubEventsHandler] for
  /// the call-index contract.
  void stubImpressionsCountHandler(
    MockResponse Function(RecordedRequest req, int callIndex) handler,
  ) {
    int callIndex = 0;
    _dispatcher.post(RegExp(r'/testImpressions/count'), (req) {
      impressionsCountRequests.add(req);
      return handler(req, callIndex++);
    });
  }

  /// Register a custom per-request handler for POST /v1/keys/cs (unique
  /// matching keys, client-side NONE mode). See [stubEventsHandler] for the
  /// call-index contract.
  void stubUniqueKeysHandler(
    MockResponse Function(RecordedRequest req, int callIndex) handler,
  ) {
    int callIndex = 0;
    _dispatcher.post(RegExp(r'/v1/keys/cs'), (req) {
      uniqueKeysRequests.add(req);
      return handler(req, callIndex++);
    });
  }

  /// Register a route handler for POST /v1/keys/ss (unique matching keys,
  /// server-side NONE mode, spec §19.6). Captures each request into
  /// [uniqueKeysSsRequests] and returns 200.
  void stubUniqueKeysSs() {
    _dispatcher.post(RegExp(r'/v1/keys/ss'), (req) {
      uniqueKeysSsRequests.add(req);
      return MockResponse().setStatusCode(200);
    });
  }

  /// Register a custom per-request handler for POST /v1/keys/ss (unique
  /// matching keys, server-side NONE mode). See [stubEventsHandler] for the
  /// call-index contract.
  void stubUniqueKeysSsHandler(
    MockResponse Function(RecordedRequest req, int callIndex) handler,
  ) {
    int callIndex = 0;
    _dispatcher.post(RegExp(r'/v1/keys/ss'), (req) {
      uniqueKeysSsRequests.add(req);
      return handler(req, callIndex++);
    });
  }

  /// Register a route handler for GET /memberships/:key requests.
  /// Returns an empty-membership response for any key.
  void stubMemberships() {
    _dispatcher.get(RegExp(r'/memberships/'), (req) {
      membershipsRequests.add(req);
      return MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode({
            'ms': {'k': <String>[], 'cn': 1000},
            'ls': {'k': <String>[], 'cn': -1},
          }));
    });
  }

  /// Register a custom per-request handler for GET /memberships/:key.
  /// The [handler] receives the request and a 0-based call index (shared
  /// across all keys, mirroring [stubSegmentChangesHandler]), letting a test
  /// return different membership data on later fetches (e.g. the catch-up
  /// fetch issued when a streaming push connection comes up, spec §11.3) than
  /// on the initial sync.
  void stubMembershipsHandler(
    MockResponse Function(RecordedRequest req, int callIndex) handler,
  ) {
    int callIndex = 0;
    _dispatcher.get(RegExp(r'/memberships/'), (req) {
      membershipsRequests.add(req);
      return handler(req, callIndex++);
    });
  }

  /// Register a route handler for GET /segmentChanges/:name requests
  /// (server-side segment refresh, spec §17.2 Axis 3). Captures each request
  /// and always responds already caught up (`till` equal to the default
  /// unregistered-segment cursor), which is sufficient for tests that only
  /// assert a fetch occurred rather than exercising cursor progression.
  void stubSegmentChanges() {
    _dispatcher.get(RegExp(r'/segmentChanges/'), (req) {
      segmentChangesRequests.add(req);
      final name = req.path.split('/').last;
      return MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode({
            'name': name,
            'added': <String>[],
            'removed': <String>[],
            'since': -1,
            'till': -1,
          }));
    });
  }

  /// Register a custom per-request handler for GET /segmentChanges/:name.
  /// The [handler] receives the request and a 0-based call index (shared
  /// across all segment names, mirroring [stubSplitChangesHandler]), so a
  /// test can return actual membership data instead of the always-empty
  /// response from [stubSegmentChanges].
  void stubSegmentChangesHandler(
    MockResponse Function(RecordedRequest req, int callIndex) handler,
  ) {
    int callIndex = 0;
    _dispatcher.get(RegExp(r'/segmentChanges/'), (req) {
      segmentChangesRequests.add(req);
      return handler(req, callIndex++);
    });
  }

  /// Register a route handler for GET /v2/auth requests.
  /// Captures each request and returns a push-enabled auth response with a
  /// JWT token granting the given [channels] (default: a single control
  /// channel). Set [pushEnabled] to false to simulate a push-disabled account.
  ///
  /// [ttlSeconds] controls the JWT `exp` claim (default 3600 s). A short TTL
  /// makes `expiresAt − refreshLeadTime` land in the past so the streaming
  /// runtime's proactive token-refresh timer (§11.3) fires promptly, which is
  /// how the refresh path becomes observable within a test window.
  void stubAuth({
    List<String> channels = const ['control_pri'],
    bool pushEnabled = true,
    int ttlSeconds = 3600,
  }) {
    _dispatcher.get(RegExp(r'/v2/auth'), (req) {
      authRequests.add(req);
      return MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode({
            'pushEnabled': pushEnabled,
            'token': pushEnabled ? _fakeJwt(channels, ttlSeconds) : '',
          }));
    });
  }

  /// Build a minimal (unsigned) JWT whose body carries an
  /// `x-ably-capability` claim granting subscribe on the given [channels],
  /// plus `iat`/`exp` timestamps as required by the spec (§19.3).
  static String _fakeJwt(List<String> channels, [int ttlSeconds = 3600]) {
    String b64(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final capability = {
      for (final c in channels) c: ['subscribe']
    };
    final header = {'alg': 'none', 'typ': 'JWT'};
    final body = {
      'x-ably-capability': jsonEncode(capability),
      'iat': now,
      'exp': now + ttlSeconds,
    };
    return '${b64(header)}.${b64(body)}.';
  }

  /// Register a route handler for GET /sse and /event-stream requests.
  /// Streams the provided SSE events back to the client.
  void stubStreaming({List<SseEvent> events = const []}) {
    _dispatcher.get(RegExp(r'/sse|/event-stream'), (req) {
      streamingRequests.add(req);
      return _streamingResponse(events: events);
    });
  }

  /// Register a route handler for GET /sse and /event-stream that delivers
  /// [events] once and then holds the connection open indefinitely, without
  /// ever replaying [events] on a later reconnect.
  ///
  /// `dart:io`'s [HttpResponse] buffers output by default and only flushes
  /// it to the socket when the response stream completes (or is explicitly
  /// flushed, which `package:mock_http_server`'s `addStream`-based writer
  /// never does) — so bytes queued on a [StreamController] that is never
  /// closed are NEVER actually transmitted to the client, no matter how
  /// long the test waits. To actually deliver [events] despite that, the
  /// FIRST connection enqueues them and then closes the stream immediately
  /// (same mechanism [stubStreaming] uses, which is proven to flush), so the
  /// client receives them before the connection naturally ends. A closed
  /// stream reads as a disconnect to the SSE client, which reconnects; every
  /// SUBSEQUENT connection (the reconnect, and any later ones) gets an empty
  /// stream that is held open forever — so [events] are delivered exactly
  /// once, never replayed. Captures each request like [stubStreaming].
  void stubStreamingHold({List<SseEvent> events = const []}) {
    var connectionIndex = 0;
    _dispatcher.get(RegExp(r'/sse|/event-stream'), (req) {
      streamingRequests.add(req);
      final ctrl = StreamController<SseEvent>();
      _openStreams.add(ctrl);
      ctrl.add(const SseEvent(event: 'keepalive', data: ''));
      if (connectionIndex == 0) {
        for (final event in events) {
          ctrl.add(event);
        }
        unawaited(ctrl.close());
      }
      connectionIndex++;
      return SseResponseBuilder.build(ctrl.stream);
    });
  }

  /// Register a route handler for GET /sse and /event-stream that opens the SSE
  /// connection and holds it open indefinitely (the stream never ends), so the
  /// connection does NOT terminate and trigger a reconnect. Captures each
  /// request. Used to isolate the proactive token-refresh path (§11.3): the only
  /// thing that can force a teardown + fresh auth is the refresh timer.
  void stubStreamingOpen() {
    _dispatcher.get(RegExp(r'/sse|/event-stream'), (req) {
      streamingRequests.add(req);
      final ctrl = StreamController<SseEvent>();
      _openStreams.add(ctrl);
      // Seed a keepalive frame so the HTTP response headers flush immediately
      // (the client's connect resolves and the SSE connection is considered
      // open); the controller is then held open so the stream never ends.
      ctrl.add(const SseEvent(event: 'keepalive', data: ''));
      return SseResponseBuilder.build(ctrl.stream);
    });
  }

  /// Register a route handler for GET /sse and /event-stream that opens the
  /// SSE connection and holds it open indefinitely (same as
  /// [stubStreamingOpen]), but returns the underlying [StreamController] so
  /// the test can push events onto it at a time of its own choosing —
  /// instead of baking a fixed event list in at stub-registration time (as
  /// [stubStreaming]/[stubStreamingHold] do).
  ///
  /// Used when an event's effect would otherwise race with another
  /// in-flight async operation triggered by the connection coming up (e.g.
  /// the push-up membership catch-up fetch, spec §11.3/§12.2): the test can
  /// wait for that operation to be observably complete (e.g. assert on a
  /// captured request count) before calling `add` on the returned
  /// controller, making the ordering deterministic.
  StreamController<SseEvent> stubStreamingInteractive() {
    final ctrl = StreamController<SseEvent>();
    _openStreams.add(ctrl);
    _dispatcher.get(RegExp(r'/sse|/event-stream'), (req) {
      streamingRequests.add(req);
      // Seed a keepalive frame so the HTTP response headers flush
      // immediately (the client's connect resolves and the SSE connection
      // is considered open).
      ctrl.add(const SseEvent(event: 'keepalive', data: ''));
      return SseResponseBuilder.build(ctrl.stream);
    });
    return ctrl;
  }

  /// Register a route handler for GET /sse and /event-stream that responds with
  /// the given HTTP [statusCode] and no event body. Captures each request.
  ///
  /// Used to simulate SSE connect failures (e.g. a `401` token error, spec
  /// §10.3/§11.3, which MUST trigger token invalidation + reconnect).
  void stubStreamingStatus(int statusCode) {
    _dispatcher.get(RegExp(r'/sse|/event-stream'), (req) {
      streamingRequests.add(req);
      return MockResponse()
          .setStatusCode(statusCode)
          .setHeader('Content-Type', 'text/event-stream; charset=utf-8')
          .setBody('');
    });
  }

  /// Serve fixture files from a suite directory.
  ///
  /// Registers:
  /// - GET /splitChanges → returns contents of split_changes.json
  /// - GET /memberships/:key → returns membership response built from segments/
  /// - POST /testImpressions/bulk → captures request body
  void stubFromFixtures(String suiteDir) {
    final splitChangesFile = File('$suiteDir/split_changes.json');
    final splitChangesBody = splitChangesFile.readAsStringSync();

    _dispatcher.get(RegExp(r'/splitChanges'), (req) {
      splitChangesRequests.add(req);
      return MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(splitChangesBody);
    });

    final segmentsDir = Directory('$suiteDir/segments');
    final segmentNames = <String>{};
    if (segmentsDir.existsSync()) {
      for (final file in segmentsDir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last.replaceAll('.json', '');
        segmentNames.add(name);
      }
    }

    _dispatcher.get(RegExp(r'/memberships/'), (req) {
      membershipsRequests.add(req);
      final key = Uri.decodeComponent(req.path.split('/').last);
      final memberships = _buildMembershipsForKey(suiteDir, segmentNames, key);
      return MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode(memberships));
    });

    _dispatcher.post(RegExp(r'/testImpressions'), (req) {
      impressionRequests.add(req);
      return MockResponse().setStatusCode(200);
    });

    _dispatcher.post(RegExp(r'/v1/keys/cs'), (req) {
      uniqueKeysRequests.add(req);
      return MockResponse().setStatusCode(200);
    });

    _dispatcher.post(RegExp(r'/events/bulk'), (req) {
      eventRequests.add(req);
      return MockResponse().setStatusCode(200);
    });
  }

  /// Returns all posted events as a flat list of event maps in wire shape:
  /// `[{"key":..,"trafficTypeName":..,"eventTypeId":..,"value":..,"timestamp":..,"properties":..}]`
  List<Map<String, dynamic>> get postedEvents {
    final List<Map<String, dynamic>> all = [];
    for (final req in eventRequests) {
      final body = jsonDecode(utf8.decode(req.body)) as List;
      for (final event in body) {
        all.add(Map<String, dynamic>.from(event as Map));
      }
    }
    return all;
  }

  static Map<String, dynamic> _buildMembershipsForKey(
    String suiteDir,
    Set<String> segmentNames,
    String key,
  ) {
    final memberOf = <String>[];
    for (final name in segmentNames) {
      final file = File('$suiteDir/segments/$name.json');
      if (file.existsSync()) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final added = (data['added'] as List?)?.cast<String>() ?? [];
        if (added.contains(key)) {
          memberOf.add(name);
        }
      }
    }

    return {
      'ms': {
        'k': memberOf,
        'cn': 1000,
      },
      'ls': {
        'k': <String>[],
        'cn': -1,
      },
    };
  }

  static MockResponse _splitChangesResponse({
    required List<Map<String, dynamic>> splits,
    required int since,
  }) {
    final payload = {
      'ff': {
        's': since,
        't': since,
        'd': splits,
      },
      'rbs': {
        's': since,
        't': since,
        'd': [],
      },
    };
    return MockResponse()
        .setStatusCode(200)
        .setHeader('Content-Type', 'application/json')
        .setBody(jsonEncode(payload));
  }

  static MockResponse _streamingResponse({
    required List<SseEvent> events,
  }) {
    final ctrl = StreamController<SseEvent>();
    for (final event in events) {
      ctrl.add(event);
    }
    ctrl.close();
    return SseResponseBuilder.build(ctrl.stream);
  }

  /// Factory to construct a SPLIT_UPDATE SSE event with the given change number.
  ///
  /// Real Split SSE frames wrap the notification in an Ably envelope where the
  /// inner notification is a JSON-encoded STRING inside the envelope's `data`
  /// field (see spec §19.3 / SSE Appendix, e.g. push_msg-split_update.txt).
  /// This double-encoding mirrors production so a real SSE parser won't
  /// false-pass on a raw notification object.
  static SseEvent splitUpdateEvent({required int changeNumber}) {
    return _ablyEnvelope(
      channel: 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_splits',
      notification: {
        'type': 'SPLIT_UPDATE',
        'changeNumber': changeNumber,
        'pcn': 1,
        'c': 2,
        'd': '',
      },
    );
  }

  /// Factory to construct an in-place `SPLIT_UPDATE` SSE event: `c: 0`
  /// (uncompressed) with the flag [definition] inline as base64(utf8(JSON))
  /// in `d`, and [pcn] matching the SDK's currently-stored change number so
  /// the in-place apply path (spec §12.1) is taken instead of a fetch
  /// fallback.
  static SseEvent splitUpdateInPlaceEvent({
    required int changeNumber,
    required int pcn,
    required Map<String, dynamic> definition,
  }) {
    return _ablyEnvelope(
      channel: 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_splits',
      notification: {
        'type': 'SPLIT_UPDATE',
        'changeNumber': changeNumber,
        'pcn': pcn,
        'c': 0,
        'd': base64.encode(utf8.encode(jsonEncode(definition))),
      },
    );
  }

  /// Factory to construct a `SPLIT_UPDATE` SSE event whose `d` is carried
  /// verbatim from the caller: [c] is the wire compression byte (`1` gzip,
  /// `2` zlib, `3` unknown, ...) and [d] the already-encoded base64 payload
  /// (spec §12.3). Use it for compressed definitions and for unsupported or
  /// corrupt payloads that [splitUpdateInPlaceEvent] cannot express.
  static SseEvent splitUpdateCompressedEvent({
    required int changeNumber,
    required int pcn,
    required int c,
    required String d,
  }) {
    return _ablyEnvelope(
      channel: 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_splits',
      notification: {
        'type': 'SPLIT_UPDATE',
        'changeNumber': changeNumber,
        'pcn': pcn,
        'c': c,
        'd': d,
      },
    );
  }

  /// Factory to construct a `SPLIT_KILL` SSE event (spec §12.1): applied in
  /// place immediately against the already-stored flag named [splitName].
  static SseEvent splitKillEvent({
    required int changeNumber,
    required String splitName,
    required String defaultTreatment,
  }) {
    return _ablyEnvelope(
      channel: 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_splits',
      notification: {
        'type': 'SPLIT_KILL',
        'changeNumber': changeNumber,
        'splitName': splitName,
        'defaultTreatment': defaultTreatment,
      },
    );
  }

  /// Factory to construct a server-side `SEGMENT_UPDATE` SSE event (spec
  /// §17.2 Axis 3): signals that [segmentName]'s own cursor has moved to
  /// [changeNumber], with no membership delta inline — the SDK MUST fetch
  /// `GET /segmentChanges/[segmentName]` to catch up.
  static SseEvent segmentUpdateEvent({
    required String segmentName,
    required int changeNumber,
  }) {
    return _ablyEnvelope(
      channel: 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_segments',
      notification: {
        'type': 'SEGMENT_UPDATE',
        'changeNumber': changeNumber,
        'segmentName': segmentName,
      },
    );
  }

  /// Factory to construct a client-side membership-channel `SEGMENT_REMOVAL`
  /// SSE event (`u: 3`, spec §12.2): applied in place against the matching
  /// key's already-stored membership set, removing [names] (no hashing —
  /// unlike `u: 2` KEY_LIST, the removal payload lists segment names
  /// directly). Set [isLarge] to target the large-segments channel/set
  /// instead of my-segments.
  static SseEvent membershipsSegmentRemovalEvent({
    required int changeNumber,
    required List<String> names,
    bool isLarge = false,
  }) {
    return _ablyEnvelope(
      channel: isLarge
          ? 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_ls_segments'
          : 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_ms_segments',
      notification: {
        'type': isLarge ? 'MEMBERSHIPS_LS_UPDATE' : 'MEMBERSHIPS_MS_UPDATE',
        'cn': changeNumber,
        'u': 3,
        'n': names,
      },
    );
  }

  /// Factory to construct a client-side membership-channel update SSE event
  /// (spec §12.2) with the notification fields passed through as given: [u]
  /// is the update strategy (`0` unbounded, `1` bounded, `2` key list, `3`
  /// segment removal), [c]/[d] the wire compression byte and base64 payload
  /// (bitmap for `u: 1`, key list for `u: 2`), [n] the segment names and [h]
  /// the jitter hash algorithm (`0` disables the fetch jitter, making fetch
  /// timing deterministic). Optional fields left `null` are omitted. Set
  /// [isLarge] to target the large-segments channel/set.
  static SseEvent membershipsUpdateEvent({
    required int u,
    required int changeNumber,
    int? c,
    String? d,
    List<String>? n,
    int? h,
    int? i,
    int? s,
    bool isLarge = false,
  }) {
    return _ablyEnvelope(
      channel: isLarge
          ? 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_ls_segments'
          : 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_ms_segments',
      notification: {
        'type': isLarge ? 'MEMBERSHIPS_LS_UPDATE' : 'MEMBERSHIPS_MS_UPDATE',
        'cn': changeNumber,
        'u': u,
        if (c != null) 'c': c,
        if (d != null) 'd': d,
        if (n != null) 'n': n,
        if (h != null) 'h': h,
        if (i != null) 'i': i,
        if (s != null) 's': s,
      },
    );
  }

  /// Build an OCCUPANCY SSE event reporting [publishers] subscribers on the
  /// control channel's occupancy meta-channel (spec §11.4). `publishers: 0`
  /// drives push DOWN (poll fallback); a subsequent non-zero value drives
  /// push back UP, which MUST trigger a catch-up `Fetch` (§11.3).
  static SseEvent occupancyEvent({required int publishers}) {
    return _ablyEnvelope(
      channel: '[?occupancy=metrics.subscribers]control_pri',
      notification: {
        'type': 'OCCUPANCY',
        'metrics': {'publishers': publishers},
      },
    );
  }

  /// Build a CONTROL SSE event with the given wire [controlType] (e.g.
  /// `STREAMING_PAUSED`/`STREAMING_RESUMED`) and [timestamp] (spec §11.3's
  /// control-type → FSM event mapping table).
  static SseEvent controlEvent({
    required String controlType,
    required int timestamp,
  }) {
    return _ablyEnvelope(
      channel: 'control_pri',
      notification: {
        'type': 'CONTROL',
        'controlType': controlType,
        'timestamp': timestamp,
      },
    );
  }

  /// Wrap [notification] in an Ably envelope, with the notification itself
  /// JSON-encoded as a STRING inside the envelope's `data` field, and emit it
  /// as a `message` SSE event.
  static SseEvent _ablyEnvelope({
    required String channel,
    required Map<String, dynamic> notification,
  }) {
    final envelope = {
      'id': 'VSEQrcq9D8:0:0',
      'clientId': 'NDEzMTY5Mzg0MA==:MjU4MzkwNDA2NA==',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'encoding': 'json',
      'channel': channel,
      'data': jsonEncode(notification),
    };
    return SseEvent(
      event: 'message',
      data: jsonEncode(envelope),
    );
  }
}
