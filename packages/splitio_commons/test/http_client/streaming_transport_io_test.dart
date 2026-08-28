@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:test/test.dart';

void main() {
  group('VM StreamingTransport (createStreamingTransport)', () {
    late HttpServer server;
    late Uri uri;

    tearDown(() async {
      await server.close(force: true);
    });

    test('yields the response status code and streams lines in order',
        () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://${server.address.host}:${server.port}/stream');

      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.write('line-1\n');
        await request.response.flush();
        request.response.write('line-2\n');
        await request.response.flush();
        request.response.write('line-3\n');
        await request.response.close();
      });

      final transport = createStreamingTransport();
      final response = await transport.connect(uri, {'X-Test': 'yes'});

      expect(response.statusCode, 200);

      final lines = await response.lines.toList();
      expect(lines, ['line-1', 'line-2', 'line-3']);

      await response.close();
    });

    test('forwards request headers to the server', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://${server.address.host}:${server.port}/');

      final receivedHeader = Completer<String?>();
      server.listen((request) async {
        receivedHeader.complete(request.headers.value('x-custom'));
        request.response.write('ok\n');
        await request.response.close();
      });

      final transport = createStreamingTransport();
      final response =
          await transport.connect(uri, {'X-Custom': 'header-value'});
      await response.lines.toList();

      expect(await receivedHeader.future, 'header-value');
      await response.close();
    });

    test('surfaces a non-200 status code faithfully', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://${server.address.host}:${server.port}/');

      server.listen((request) async {
        request.response.statusCode = 404;
        request.response.write('not found\n');
        await request.response.close();
      });

      final transport = createStreamingTransport();
      final response = await transport.connect(uri, {});

      expect(response.statusCode, 404);
      await response.close();
    });

    test('close() stops the stream and is idempotent', () async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      uri = Uri.parse('http://${server.address.host}:${server.port}/');

      // Keep the connection open indefinitely (never call response.close()).
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.write('first\n');
        await request.response.flush();
        // Intentionally never closed by the server.
      });

      final transport = createStreamingTransport();
      final response = await transport.connect(uri, {});
      expect(response.statusCode, 200);

      final done = Completer<void>();
      response.lines.listen(
        (_) {},
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      // The stream is live and has not completed on its own.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(done.isCompleted, isFalse);

      // Closing tears down the connection and completes the stream.
      await response.close();
      await done.future.timeout(const Duration(seconds: 2));

      // Idempotent: a second close (and a late one) must not throw.
      await response.close();
      await response.close();
    });
  });
}
