import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

void main() {
  group('MockBackend', () {
    late MockBackend backend;
    late HttpClient client;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await backend.shutdown();
    });

    test('splitChanges response can be received', () async {
      backend.stubSplitChanges();

      final req = await client.getUrl(Uri.parse('${backend.url}splitChanges'));
      final resp = await req.close();
      final body = jsonDecode(await utf8.decodeStream(resp));

      expect(body['ff'], isNotNull);
      expect(body['rbs'], isNotNull);
      expect(backend.splitChangesRequests, hasLength(1));
    });

    test('SSE stream delivers SPLIT_UPDATE event', () async {
      backend.stubStreaming(events: [
        MockBackend.splitUpdateEvent(changeNumber: 42),
      ]);

      final req = await client.getUrl(Uri.parse('${backend.url}sse'));
      req.headers.set('Accept', 'text/event-stream');
      final resp = await req.close();
      final lines = await resp
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();

      expect(lines, contains(startsWith('data:')));
      expect(backend.streamingRequests, hasLength(1));
    });
  });
}
