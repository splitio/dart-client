import 'dart:async';

import 'http_status_action.dart';

/// Axis-1 SPI for acquiring a long-lived streaming HTTP connection (spec §6, §11.0).
///
/// This is the platform-specific *raw connection acquisition* layer — the same
/// "network I/O on this runtime" layer as `SplitHttpClient`, but the streaming
/// flavor rather than the buffered request/response flavor. It varies by Dart
/// runtime (VM `dart:io`/`package:http` streamed read vs. web `EventSource`/
/// `fetch` streaming) and is the test seam for feeding canned SSE frames.
///
/// SSE *framing* (the `event`/`data`/`id` read loop, keepalive handling,
/// `onMessage` dispatch) is NOT this SPI's concern — it is shared/concrete
/// (`EventSourceClient`, a later task) and MUST be identical on every platform.
/// This SPI only yields the raw, newline-delimited line stream plus the HTTP
/// status of the initial response.
abstract class StreamingTransport {
  /// Opens a long-lived streaming connection to [uri] with the given [headers].
  ///
  /// Returns a [StreamingResponse] carrying the HTTP status code of the initial
  /// response and the raw line stream. Returns a [Future] because a real socket
  /// connect (VM) and streaming `fetch` (web) are inherently asynchronous; the
  /// spec's §6 pseudo-signature (`StreamingResponse connect(Uri, headers)`) is
  /// language-agnostic and platform impls bridge that async internally.
  Future<StreamingResponse> connect(Uri uri, Map<String, String> headers);
}

/// The result of a [StreamingTransport.connect] call (spec §6, §11.0).
///
/// Carries the HTTP [statusCode] of the initial response and a raw [lines]
/// stream — one string per newline-delimited line as received from the server.
/// Framing into SSE events is done by a higher, shared layer.
class StreamingResponse {
  /// HTTP status code of the initial streaming response.
  final int statusCode;

  /// Raw line stream: one string per newline-delimited line, in order.
  ///
  /// This is a **single-subscription** stream — listening more than once MUST
  /// throw (a `StateError`). The higher, shared SSE framing layer
  /// (`EventSourceClient`, task 4.2) is the sole intended subscriber.
  ///
  /// The stream closes (its `onDone` fires) when the connection ends naturally
  /// or when [close] is called.
  final Stream<String> lines;

  final Future<void> Function() _onClose;

  StreamingResponse({
    required this.statusCode,
    required this.lines,
    required Future<void> Function() onClose,
  }) : _onClose = onClose;

  /// The §10.3 taxonomy action for this response's [statusCode].
  ///
  /// Convenience over [classifyStatus] so the streaming FSM/manager (task 4.7)
  /// can map the initial connect status to policy events (e.g. `authFailure` →
  /// InvalidateToken + reconnect; `transientRetry` → backoff/reconnect;
  /// `uriTooLong`/`doNotRetry` → non-retryable stop). This getter is pure — the
  /// transport itself never decides to reconnect; that is the FSM's job (§11).
  HttpStatusAction get action => classifyStatus(statusCode);

  /// Closes the long-lived connection and stops line emission.
  ///
  /// Long-lived streaming connections MUST be closeable so the streaming state
  /// machine can tear down / reconnect (spec §11.3). The spec does not model
  /// close explicitly on the SPI, so it is provided here and delegates to the
  /// platform-supplied teardown.
  ///
  /// [close] MUST be idempotent: calling it twice, calling it after the stream
  /// has already completed, or calling it before anyone listened MUST NOT
  /// throw. Production platform impls (tasks 3.2/3.3) MUST likewise guard their
  /// teardown so a repeated/late close is a no-op rather than a
  /// "Cannot close, already closing" race.
  Future<void> close() => _onClose();
}
