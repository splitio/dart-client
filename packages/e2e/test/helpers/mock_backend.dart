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

  /// Captured POST requests to /v1/keys/cs for assertions.
  final List<RecordedRequest> uniqueKeysRequests = [];

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
    for (final req in impressionRequests) {
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

  /// Register a route handler for GET /memberships/:key requests.
  /// Returns an empty-membership response for any key.
  void stubMemberships() {
    _dispatcher.get(RegExp(r'/memberships/'), (req) {
      return MockResponse()
          .setStatusCode(200)
          .setHeader('Content-Type', 'application/json')
          .setBody(jsonEncode({
            'ms': {'k': <String>[], 'cn': 1000},
            'ls': {'k': <String>[], 'cn': -1},
          }));
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
      final key = req.path.split('/').last;
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
