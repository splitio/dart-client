import 'dart:async';
import 'dart:convert';

import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart';

import 'streaming_transport.dart';

/// Web implementation of the [StreamingTransport] SPI (spec §6, §11.0).
///
/// Uses the browser Fetch API (via `package:fetch_client`) to open a long-lived
/// streamed response and exposes its body as a raw, newline-delimited line
/// stream. SSE *framing* is intentionally NOT performed here — that is a shared,
/// higher layer (`EventSourceClient`). This file only acquires the raw
/// connection, which is the sole platform-specific concern.
///
/// This is the web-specific platform file. It is compiled only on web targets
/// via the conditional import in `streaming_transport_factory.dart`, which is
/// why it may import `package:fetch_client` (a browser Fetch API binding). No
/// other file in the package imports web-only libraries.
class WebStreamingTransport implements StreamingTransport {
  /// Builds the underlying `package:http` [Client] used to issue the request.
  ///
  /// Defaults to a [FetchClient] with CORS mode (streaming SSE endpoints are
  /// cross-origin). A factory is injected in tests so the streamed response can
  /// be stubbed without a live network — the client is created per [connect]
  /// call so each connection owns its own abortable client.
  final Client Function() _clientFactory;

  /// Creates a web streaming transport.
  ///
  /// [clientFactory] overrides the default [FetchClient] construction; it is the
  /// test seam for feeding a canned streamed response.
  WebStreamingTransport({Client Function()? clientFactory})
      : _clientFactory = clientFactory ??
            (() => FetchClient(
                  mode: RequestMode.cors,
                  credentials: RequestCredentials.sameOrigin,
                ));

  @override
  Future<StreamingResponse> connect(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = _clientFactory();
    final request = Request('GET', uri)..headers.addAll(headers);

    final StreamedResponse streamed;
    try {
      // `send` returns a streamed response whose body is read incrementally —
      // this is what keeps the connection long-lived rather than buffering.
      streamed = await client.send(request);
    } catch (_) {
      client.close();
      rethrow;
    }

    // Raw newline-delimited lines: decode the byte stream as UTF-8 and split on
    // line breaks. `streamed.stream` is single-subscription (from `http`), which
    // satisfies the SPI's single-subscription contract for `lines`.
    final lines =
        streamed.stream.transform(utf8.decoder).transform(const LineSplitter());

    var closed = false;
    Future<void> close() async {
      // Idempotent: a repeated or late close is a no-op. Closing the client
      // aborts the in-flight fetch (via its AbortController), tearing down the
      // connection and completing the line stream.
      if (closed) return;
      closed = true;
      client.close();
    }

    return StreamingResponse(
      statusCode: streamed.statusCode,
      lines: lines,
      onClose: close,
    );
  }
}

/// Factory referenced by the conditional-import selector
/// (`streaming_transport_factory.dart`) on web targets.
StreamingTransport createStreamingTransport() => WebStreamingTransport();
