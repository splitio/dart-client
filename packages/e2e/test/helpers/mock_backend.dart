import 'dart:async';
import 'dart:convert';

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

  /// Start the mock server and register the dispatcher.
  Future<void> start() async {
    _server.dispatcher = _dispatcher;
    await _server.start();
  }

  /// Stop the mock server and clean up resources.
  Future<void> shutdown() => _server.shutdown();

  /// Base URL of the running mock server.
  String get url => _server.url;

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

  /// Register a route handler for GET /sse and /event-stream requests.
  /// Streams the provided SSE events back to the client.
  void stubStreaming({List<SseEvent> events = const []}) {
    _dispatcher.get(RegExp(r'/sse|/event-stream'), (req) {
      streamingRequests.add(req);
      return _streamingResponse(events: events);
    });
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
  static SseEvent splitUpdateEvent({required int changeNumber}) {
    return SseEvent(
      event: 'message',
      data: jsonEncode({
        'type': 'SPLIT_UPDATE',
        'changeNumber': changeNumber,
        'pcn': 1,
        'c': 2,
        'd': '',
      }),
    );
  }
}
