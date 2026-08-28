import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'streaming_transport.dart';

/// VM ([dart:io] via `package:http`) implementation of [StreamingTransport].
///
/// This is the platform-specific raw connection acquisition layer for the Dart
/// VM (servers, CLI, native apps). It uses `package:http`'s streamed
/// [http.Client.send] so the response body is consumed incrementally rather
/// than buffered — essential for a long-lived SSE connection.
///
/// `dart:io` is not imported directly: `package:http` provides the streamed
/// read on the VM without it, keeping this file free of direct `dart:io` usage.
StreamingTransport createStreamingTransport() => _IoStreamingTransport();

class _IoStreamingTransport implements StreamingTransport {
  @override
  Future<StreamingResponse> connect(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      request.headers.addAll(headers);

      final response = await client.send(request);

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      var closed = false;
      Future<void> close() async {
        if (closed) return;
        closed = true;
        client.close();
      }

      return StreamingResponse(
        statusCode: response.statusCode,
        lines: lines,
        onClose: close,
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }
}
