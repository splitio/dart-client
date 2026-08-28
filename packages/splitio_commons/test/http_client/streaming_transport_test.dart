import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/http_client/http_client_testing.dart';
import 'package:test/test.dart';

void main() {
  group('FakeStreamingTransport', () {
    test('connect returns the configured statusCode', () async {
      final transport = FakeStreamingTransport(statusCode: 401);

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      expect(response.statusCode, 401);
    });

    test('emits enqueued lines in order and then closes', () async {
      final transport = FakeStreamingTransport(
        lines: ['event: message', 'data: hello', ''],
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      expect(
        await response.lines.toList(),
        ['event: message', 'data: hello', ''],
      );
    });

    test('close() stops emission', () async {
      final transport = FakeStreamingTransport(
        lines: ['a', 'b', 'c', 'd'],
      );

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      final received = <String>[];
      final done = response.lines.listen(received.add).asFuture<void>();

      await response.close();
      await done;

      // Emission was interrupted, so not all lines arrive.
      expect(received.length, lessThan(4));
    });

    test('connect records the uri and headers', () async {
      final transport = FakeStreamingTransport();
      final uri = Uri.parse(
        'https://streaming.example.com/sse?channels=c1&accessToken=tok',
      );
      final headers = {'Accept': 'text/event-stream'};

      await transport.connect(uri, headers);

      expect(transport.lastUri, uri);
      expect(transport.lastHeaders, headers);
      expect(transport.connectCount, 1);
    });

    test('emits nothing and closes for an empty lines list', () async {
      final transport = FakeStreamingTransport(lines: const []);

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      expect(await response.lines.toList(), isEmpty);
    });

    test('close before anyone listens does not throw', () async {
      final transport = FakeStreamingTransport(lines: ['a', 'b']);

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      await expectLater(response.close(), completes);
    });

    test('double close is idempotent and does not throw', () async {
      final transport = FakeStreamingTransport(lines: ['a', 'b']);

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      await response.close();
      await expectLater(response.close(), completes);
    });

    test('close after natural completion does not throw', () async {
      final transport = FakeStreamingTransport(lines: ['a']);

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      await response.lines.toList();
      await expectLater(response.close(), completes);
    });

    test('lines is single-subscription (listening twice throws)', () async {
      final transport = FakeStreamingTransport(lines: ['a']);

      final response = await transport.connect(
        Uri.parse('https://streaming.example.com/sse'),
        const {},
      );

      response.lines.listen((_) {});
      expect(() => response.lines.listen((_) {}), throwsStateError);
    });

    test('is usable as a StreamingTransport', () async {
      final StreamingTransport transport = FakeStreamingTransport(
        lines: ['x'],
        statusCode: 200,
      );

      final response =
          await transport.connect(Uri.parse('https://e.com/sse'), const {});

      expect(response.statusCode, 200);
      expect(await response.lines.toList(), ['x']);
    });
  });

  group('StreamingResponse', () {
    test('close delegates to the supplied onClose callback', () async {
      var closed = false;
      final response = StreamingResponse(
        statusCode: 200,
        lines: const Stream.empty(),
        onClose: () async => closed = true,
      );

      await response.close();

      expect(closed, isTrue);
    });
  });
}
