import 'dart:async';

import '../streaming_transport.dart';

/// A test double for [StreamingTransport] usable by any package's tests.
///
/// Enqueue the canned lines and status code the next [connect] should return,
/// then inspect [lastUri] / [lastHeaders] to assert on the connection request.
///
/// Emitted lines are delivered in order and the stream closes once they are
/// exhausted. Calling [StreamingResponse.close] on the returned response stops
/// any pending emission.
class FakeStreamingTransport implements StreamingTransport {
  /// Lines the next [connect] call will emit, in order.
  List<String> lines;

  /// Status code the next [connect] call will report.
  int statusCode;

  /// The [uri] passed to the most recent [connect] call, or `null` if none.
  Uri? lastUri;

  /// The headers passed to the most recent [connect] call, or `null` if none.
  Map<String, String>? lastHeaders;

  /// Number of times [connect] has been called.
  int connectCount = 0;

  /// When true, the response stream is held open after [lines] are exhausted
  /// (it does NOT complete), so the consumer never sees `onDone`. Useful for
  /// tests that need a stable, long-lived connection (e.g. asserting a
  /// proactive refresh timer without a reconnect firing). [StreamingResponse.close]
  /// still tears it down.
  bool keepOpen;

  FakeStreamingTransport({
    this.lines = const [],
    this.statusCode = 200,
    this.keepOpen = false,
  });

  @override
  Future<StreamingResponse> connect(
      Uri uri, Map<String, String> headers) async {
    lastUri = uri;
    lastHeaders = Map<String, String>.from(headers);
    connectCount++;

    final controller = StreamController<String>();
    var closed = false;

    Future<void> pump() async {
      for (final line in lines) {
        if (closed) return;
        // Yield to the event loop so close() can interrupt mid-emission.
        await Future<void>.delayed(Duration.zero);
        if (closed) return;
        controller.add(line);
      }
      // Hold the stream open (never complete) when requested, so the consumer
      // does not observe onDone and schedule a reconnect.
      if (keepOpen) return;
      if (!closed && !controller.isClosed) await controller.close();
    }

    unawaited(pump());

    return StreamingResponse(
      statusCode: statusCode,
      lines: controller.stream,
      onClose: () async {
        closed = true;
        // Do not await: a single-subscription controller's close() future
        // only completes once its onDone is delivered, which never happens
        // if nobody ever listened — awaiting it would hang. Firing it is
        // enough to tear down the stream.
        if (!controller.isClosed) unawaited(controller.close());
      },
    );
  }
}
