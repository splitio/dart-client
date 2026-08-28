// This test exercises WebStreamingTransport's transport logic (status code,
// UTF-8 line splitting, idempotent close) on the Dart VM by injecting a stubbed
// `package:http` streaming client. No browser is required because the real
// browser Fetch path (package:fetch_client's FetchClient) is swapped out via the
// `clientFactory` seam — so this test runs in the default `dart test` VM run and
// does NOT need `dart test -p chrome`.
//
// The one behavior that genuinely needs a browser — that the *real* FetchClient
// aborts the in-flight fetch on close() — cannot be observed on the VM (the io
// shim throws UnsupportedError). That path is covered by the shared streaming
// integration tests running under a browser; here we assert close() tears down
// the injected client and is idempotent.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/http_client/streaming_transport_web.dart';
import 'package:test/test.dart';

StreamedResponse _streamedFromLines(
  List<String> lines, {
  int statusCode = 200,
}) {
  final body = lines.map((l) => utf8.encode('$l\n')).expand((b) => b).toList();
  return StreamedResponse(
    Stream.value(body),
    statusCode,
  );
}

void main() {
  group('WebStreamingTransport', () {
    test('is a StreamingTransport', () {
      final StreamingTransport transport = WebStreamingTransport(
        clientFactory: () => MockClient.streaming(
          (request, bodyStream) async => _streamedFromLines(const []),
        ),
      );
      expect(transport, isA<StreamingTransport>());
    });

    test('exposes the response statusCode', () async {
      final transport = WebStreamingTransport(
        clientFactory: () => MockClient.streaming(
          (request, bodyStream) async =>
              _streamedFromLines(const [], statusCode: 401),
        ),
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      expect(response.statusCode, 401);
    });

    test('decodes UTF-8 and splits the body into newline-delimited lines',
        () async {
      final transport = WebStreamingTransport(
        clientFactory: () => MockClient.streaming(
          (request, bodyStream) async => _streamedFromLines(
            ['event: message', 'data: héllo', ''],
          ),
        ),
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      expect(
        await response.lines.toList(),
        ['event: message', 'data: héllo', ''],
      );
    });

    test('forwards the uri and headers to the request', () async {
      Uri? seenUri;
      Map<String, String>? seenHeaders;
      final transport = WebStreamingTransport(
        clientFactory: () => MockClient.streaming(
          (request, bodyStream) async {
            seenUri = request.url;
            seenHeaders = request.headers;
            return _streamedFromLines(const []);
          },
        ),
      );

      final uri = Uri.parse('https://streaming.example.com/sse?channels=c1');
      await transport.connect(uri, {'Accept': 'text/event-stream'});

      expect(seenUri, uri);
      expect(seenHeaders?['Accept'], 'text/event-stream');
    });

    test('emits nothing and closes for an empty body', () async {
      final transport = WebStreamingTransport(
        clientFactory: () => MockClient.streaming(
          (request, bodyStream) async => _streamedFromLines(const []),
        ),
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      expect(await response.lines.toList(), isEmpty);
    });

    test('close() closes the underlying client', () async {
      var closeCount = 0;
      final transport = WebStreamingTransport(
        clientFactory: () => _ClosableMockClient(() => closeCount++),
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      await response.close();

      expect(closeCount, 1);
    });

    test('close() is idempotent', () async {
      var closeCount = 0;
      final transport = WebStreamingTransport(
        clientFactory: () => _ClosableMockClient(() => closeCount++),
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      await response.close();
      await expectLater(response.close(), completes);

      // The underlying client is closed at most once.
      expect(closeCount, 1);
    });

    test('close before anyone listens does not throw', () async {
      final transport = WebStreamingTransport(
        clientFactory: () => MockClient.streaming(
          (request, bodyStream) async => _streamedFromLines(['a', 'b']),
        ),
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      await expectLater(response.close(), completes);
    });

    test('close after natural completion does not throw', () async {
      final transport = WebStreamingTransport(
        clientFactory: () => MockClient.streaming(
          (request, bodyStream) async => _streamedFromLines(['a']),
        ),
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      await response.lines.toList();
      await expectLater(response.close(), completes);
    });

    test('lines is single-subscription (listening twice throws)', () async {
      final transport = WebStreamingTransport(
        clientFactory: () => MockClient.streaming(
          (request, bodyStream) async => _streamedFromLines(['a']),
        ),
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      response.lines.listen((_) {});
      expect(() => response.lines.listen((_) {}), throwsStateError);
    });
  });
}

/// A [MockClient] variant that reports when [close] is called, so the transport's
/// teardown can be observed on the VM.
class _ClosableMockClient extends MockClient {
  _ClosableMockClient(this._onClose)
      : super.streaming(
          (request, bodyStream) async => StreamedResponse(
            const Stream<List<int>>.empty(),
            200,
          ),
        );

  final void Function() _onClose;

  @override
  void close() {
    _onClose();
    super.close();
  }
}
