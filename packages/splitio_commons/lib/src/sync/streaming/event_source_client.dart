import 'dart:async';
import 'dart:convert';

import 'package:splitio_commons/src/http_client/http_client.dart';

/// A single SSE frame decoded by [EventSourceClient] (spec §11.0).
///
/// This is the raw, *uncategorized* result of SSE framing. Turning it into a
/// data/control/occupancy/error notification is the `NotificationProcessor`'s
/// job (§11.4, task 4.3) — this layer only unwraps the Ably double-encoding and
/// hands up what it found.
///
/// For a `message` event the wire payload is an Ably envelope
/// (`{id, clientId, timestamp, encoding, channel, data}`) whose `data` field is
/// itself a JSON-encoded STRING of the inner notification
/// (`{type, changeNumber, ...}`). After framing:
/// - [channel] is the envelope's channel,
/// - [data] is the decoded inner notification map,
/// - [rawData] is the still-encoded inner string (the envelope's `data`).
///
/// For a non-`message` event (e.g. Ably `event: error`) there is no Ably
/// envelope: [event] is the event name, [data] is the JSON-decoded payload if
/// it parsed as an object, and [rawData] is the raw `data:` buffer.
class RawNotification {
  /// The SSE `id:` field of the frame, if any.
  final String? id;

  /// The Ably channel the message arrived on (`message` events only).
  final String? channel;

  /// The SSE event type (`message` by default, or e.g. `error`).
  final String event;

  /// The decoded inner notification map, or `null` if it was not a JSON object.
  final Map<String, dynamic>? data;

  /// The raw, undecoded `data:` payload (inner string for `message` events).
  final String? rawData;

  const RawNotification({
    required this.event,
    this.id,
    this.channel,
    this.data,
    this.rawData,
  });
}

/// Shared, concrete SSE read loop that sits above the [StreamingTransport] SPI
/// and below the streaming FSM/manager (spec §11.0).
///
/// It consumes the transport's raw newline-delimited line stream, assembles SSE
/// frames (`event`/`data`/`id`, blank-line dispatch, `:` keepalive comments),
/// unwraps the Ably double-encoding for `message` events, and forwards each
/// frame via `onMessage`. It is platform-agnostic and identical on every
/// runtime.
///
/// It contains NO timers and NO reconnect logic — connection lifecycle policy
/// (backoff, reconnect, poll fallback) belongs to the FSM/manager (task 4.7).
class EventSourceClient {
  final StreamingTransport _transport;

  StreamingResponse? _response;
  StreamSubscription<String>? _subscription;
  bool _closed = false;

  EventSourceClient({required StreamingTransport transport})
      : _transport = transport;

  /// HTTP status code of the initial streaming response, or `null` before
  /// [connect] has resolved.
  int? get statusCode => _response?.statusCode;

  /// Opens the streaming connection and begins framing.
  ///
  /// [onMessage] is invoked once per dispatched SSE frame. [onError] receives
  /// framing/decoding errors (a malformed frame is skipped, not fatal — the read
  /// loop survives). [onOpen] fires once the connection is established. [onDone]
  /// fires when the line stream completes naturally or after [close].
  ///
  /// The connect [statusCode] is always exposed via [statusCode] regardless of
  /// value; a non-2xx status still yields whatever lines the transport emits and
  /// completes gracefully. Mapping status → reconnect/stop is the FSM's job.
  Future<void> connect(
    Uri uri,
    Map<String, String> headers, {
    required void Function(RawNotification) onMessage,
    void Function(Object error, StackTrace stackTrace)? onError,
    void Function()? onOpen,
    void Function()? onDone,
  }) async {
    final response = await _transport.connect(uri, headers);
    _response = response;

    if (_closed) {
      // close() was called while connecting — tear down immediately.
      await response.close();
      onDone?.call();
      return;
    }

    onOpen?.call();

    // SSE frame accumulator.
    String eventType = 'message';
    final dataBuffer = StringBuffer();
    var hasData = false;
    String? lastId;

    void reset() {
      eventType = 'message';
      dataBuffer.clear();
      hasData = false;
    }

    void dispatch() {
      if (!hasData) {
        // A frame with no data lines (e.g. only an id: line then blank) is not
        // dispatched as a message per the SSE spec.
        reset();
        return;
      }
      final rawData = dataBuffer.toString();
      final currentEvent = eventType;
      final currentId = lastId;
      reset();
      try {
        onMessage(_decodeFrame(
          event: currentEvent,
          id: currentId,
          rawData: rawData,
        ));
      } catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    }

    _subscription = response.lines.listen(
      (line) {
        // Blank line dispatches the current frame.
        if (line.isEmpty) {
          dispatch();
          return;
        }
        // Comment / keepalive line: starts with ':'. No-op (never dispatches).
        if (line.startsWith(':')) {
          return;
        }
        final colon = line.indexOf(':');
        final String field;
        String value;
        if (colon == -1) {
          // A line with no colon is a field name with empty value (SSE spec).
          field = line;
          value = '';
        } else {
          field = line.substring(0, colon);
          value = line.substring(colon + 1);
          // Strip a single leading space after the colon.
          if (value.startsWith(' ')) {
            value = value.substring(1);
          }
        }
        switch (field) {
          case 'event':
            eventType = value;
            break;
          case 'data':
            if (hasData) dataBuffer.write('\n');
            dataBuffer.write(value);
            hasData = true;
            break;
          case 'id':
            lastId = value;
            break;
          default:
            // Unknown field — ignore per SSE spec.
            break;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        onError?.call(error, stackTrace);
      },
      onDone: () {
        onDone?.call();
      },
      cancelOnError: false,
    );
  }

  /// Decodes a dispatched frame into a [RawNotification].
  ///
  /// For `message` events this unwraps the Ably envelope and the double-encoded
  /// inner notification. For other events (e.g. `error`) it best-effort decodes
  /// the raw payload as JSON. Malformed JSON throws — the caller ([dispatch])
  /// routes it to `onError` and skips the frame.
  RawNotification _decodeFrame({
    required String event,
    required String? id,
    required String rawData,
  }) {
    if (event == 'message') {
      final envelope = jsonDecode(rawData);
      if (envelope is! Map<String, dynamic>) {
        throw const FormatException(
            'SSE message envelope is not a JSON object');
      }
      final channel = envelope['channel'] as String?;
      final innerRaw = envelope['data'];
      if (innerRaw is! String) {
        throw const FormatException(
            'Ably envelope "data" is not a JSON-encoded string');
      }
      final inner = jsonDecode(innerRaw);
      final innerMap = inner is Map<String, dynamic> ? inner : null;
      return RawNotification(
        event: event,
        id: id,
        channel: channel,
        data: innerMap,
        rawData: innerRaw,
      );
    }

    // Non-message event (error / system): best-effort decode the payload.
    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(rawData);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } on FormatException {
      decoded = null;
    }
    return RawNotification(
      event: event,
      id: id,
      channel: null,
      data: decoded,
      rawData: rawData,
    );
  }

  /// Closes the connection and cancels the read loop.
  ///
  /// Idempotent: calling it twice, before [connect] resolves, or after the
  /// stream has already completed MUST NOT throw.
  Future<void> close() async {
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _response?.close();
  }
}
