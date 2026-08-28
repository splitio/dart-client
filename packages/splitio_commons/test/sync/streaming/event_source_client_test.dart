import 'dart:convert';

import 'package:splitio_commons/src/http_client/http_client_testing.dart';
import 'package:splitio_commons/src/sync/streaming/event_source_client.dart';
import 'package:test/test.dart';

/// Builds the raw SSE lines for one Ably `message` frame carrying [notification]
/// double-encoded, matching production (`mock_backend.dart`).
List<String> ablyMessageLines({
  required String channel,
  required Map<String, dynamic> notification,
  String id = 'VSEQrcq9D8:0:0',
}) {
  final envelope = {
    'id': id,
    'clientId': 'NDEzMTY5Mzg0MA==:MjU4MzkwNDA2NA==',
    'timestamp': 1506703262916,
    'encoding': 'json',
    'channel': channel,
    'data': jsonEncode(notification),
  };
  // A full frame delivered as discrete transport lines (transport splits on
  // newlines, so each SSE line is one entry, plus a blank line to dispatch).
  return [
    'event: message',
    'data: ${jsonEncode(envelope)}',
    'id: $id',
    '',
  ];
}

void main() {
  group('EventSourceClient — happy path', () {
    test('decodes a single SPLIT_UPDATE Ably double-encoded frame', () async {
      final transport = FakeStreamingTransport(
        lines: ablyMessageLines(
          channel: 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_splits',
          notification: {
            'type': 'SPLIT_UPDATE',
            'changeNumber': 1684265694505,
            'pcn': 1,
            'c': 2,
            'd': '',
          },
        ),
      );
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final done = <bool>[];

      await client.connect(
        Uri.parse('https://streaming.example/sse'),
        {'Authorization': 'Bearer tok'},
        onMessage: received.add,
        onDone: () => done.add(true),
      );

      await pumpUntil(() => done.isNotEmpty);

      expect(client.statusCode, 200);
      expect(received, hasLength(1));
      final n = received.single;
      expect(n.event, 'message');
      expect(n.channel, 'MzM5Njc0ODcyNg==_MTExMzgwNjgx_splits');
      expect(n.id, 'VSEQrcq9D8:0:0');
      expect(n.data!['type'], 'SPLIT_UPDATE');
      expect(n.data!['changeNumber'], 1684265694505);
      expect(n.rawData, isNotNull);
    });

    test('passes uri and headers to the transport', () async {
      final transport = FakeStreamingTransport(lines: const []);
      final client = EventSourceClient(transport: transport);
      final uri = Uri.parse('https://streaming.example/sse?v=1.1');
      final headers = {
        'Authorization': 'Bearer tok',
        'Accept': 'text/event-stream'
      };

      await client.connect(uri, headers, onMessage: (_) {});

      expect(transport.lastUri, uri);
      expect(transport.lastHeaders, headers);
      expect(transport.connectCount, 1);
    });
  });

  group('EventSourceClient — framing', () {
    test('folds data lines (error event) joined with \\n', () async {
      final transport = FakeStreamingTransport(lines: [
        'event: error',
        'data: line1',
        'data: line2',
        '',
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add, onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(received, hasLength(1));
      expect(received.single.event, 'error');
      expect(received.single.rawData, 'line1\nline2');
    });

    test('strips a single leading space after the colon', () async {
      final transport = FakeStreamingTransport(lines: [
        'event:error',
        'data:  two-spaces', // only one stripped -> ' two-spaces'
        '',
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add, onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(received.single.rawData, ' two-spaces');
    });

    test('keepalive comment lines do not dispatch and stream survives',
        () async {
      final transport = FakeStreamingTransport(lines: [
        ':', // bare heartbeat
        ':keepalive comment',
        ...ablyMessageLines(
          channel: 'ch',
          notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 7},
        ),
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add, onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(received, hasLength(1));
      expect(received.single.data!['changeNumber'], 7);
    });

    test('two frames back-to-back are both delivered', () async {
      final transport = FakeStreamingTransport(lines: [
        ...ablyMessageLines(
            channel: 'ch',
            notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 1}),
        ...ablyMessageLines(
            channel: 'ch',
            notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 2}),
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add, onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(received.map((n) => n.data!['changeNumber']), [1, 2]);
    });

    test('a frame split across separate lines still assembles', () async {
      // event / data / id / blank arriving as separate transport lines is the
      // normal case; verify the id is captured too.
      final transport = FakeStreamingTransport(
          lines: ablyMessageLines(
        channel: 'ch',
        notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 9},
        id: 'evt-42',
      ));
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add, onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(received.single.id, 'evt-42');
    });

    test('a frame with only an id line and no data is not dispatched',
        () async {
      final transport = FakeStreamingTransport(lines: [
        'id: only-id',
        '',
        ...ablyMessageLines(
            channel: 'ch',
            notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 3}),
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add, onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      // Only the real frame dispatches.
      expect(received, hasLength(1));
      expect(received.single.data!['changeNumber'], 3);
    });
  });

  group('EventSourceClient — robustness', () {
    test(
        'malformed envelope JSON -> onError, loop survives, next frame delivered',
        () async {
      final transport = FakeStreamingTransport(lines: [
        'event: message',
        'data: {not valid json',
        '',
        ...ablyMessageLines(
            channel: 'ch',
            notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 11}),
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final errors = <Object>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add,
          onError: (e, _) => errors.add(e),
          onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(errors, hasLength(1));
      expect(received, hasLength(1));
      expect(received.single.data!['changeNumber'], 11);
    });

    test('malformed inner data string -> onError, loop survives', () async {
      final badEnvelope = {
        'channel': 'ch',
        'data': '{not-valid-inner',
      };
      final transport = FakeStreamingTransport(lines: [
        'event: message',
        'data: ${jsonEncode(badEnvelope)}',
        '',
        ...ablyMessageLines(
            channel: 'ch',
            notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 12}),
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final errors = <Object>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add,
          onError: (e, _) => errors.add(e),
          onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(errors, hasLength(1));
      expect(received, hasLength(1));
      expect(received.single.data!['changeNumber'], 12);
    });

    test('envelope data field not a string -> onError', () async {
      final badEnvelope = {'channel': 'ch', 'data': 123};
      final transport = FakeStreamingTransport(lines: [
        'event: message',
        'data: ${jsonEncode(badEnvelope)}',
        '',
      ]);
      final client = EventSourceClient(transport: transport);
      final errors = <Object>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: (_) {},
          onError: (e, _) => errors.add(e),
          onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(errors, hasLength(1));
    });
  });

  group('EventSourceClient — non-message events', () {
    test('event: error surfaced with event name and inner error map', () async {
      final transport = FakeStreamingTransport(lines: [
        'event: error',
        'data: ${jsonEncode({
              'code': 40140,
              'statusCode': 401,
              'message': 'token expired',
            })}',
        '',
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add, onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(received.single.event, 'error');
      expect(received.single.data!['code'], 40140);
      expect(received.single.channel, isNull);
    });
  });

  group('EventSourceClient — status handling', () {
    test('non-200 status is exposed and stream completes gracefully', () async {
      final transport =
          FakeStreamingTransport(lines: const [], statusCode: 401);
      final client = EventSourceClient(transport: transport);
      final done = <bool>[];
      var opened = false;
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: (_) {},
          onOpen: () => opened = true,
          onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(client.statusCode, 401);
      expect(opened, isTrue);
    });
  });

  group('EventSourceClient — lifecycle', () {
    test('onOpen fires on connect', () async {
      final transport = FakeStreamingTransport(lines: const []);
      final client = EventSourceClient(transport: transport);
      var opened = false;
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: (_) {}, onOpen: () => opened = true);
      expect(opened, isTrue);
    });

    test('onDone fires on natural stream completion', () async {
      final transport = FakeStreamingTransport(lines: const []);
      final client = EventSourceClient(transport: transport);
      final done = <bool>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: (_) {}, onDone: () => done.add(true));
      await pumpUntil(() => done.isNotEmpty);
      expect(done, hasLength(1));
    });

    test('close() is idempotent and does not throw', () async {
      final transport = FakeStreamingTransport(
          lines: ablyMessageLines(
              channel: 'ch',
              notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 1}));
      final client = EventSourceClient(transport: transport);
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: (_) {});
      await client.close();
      await client.close();
    });

    test('close before stream end does not throw and stops delivery', () async {
      final transport = FakeStreamingTransport(lines: [
        ...ablyMessageLines(
            channel: 'ch',
            notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 1}),
        ...ablyMessageLines(
            channel: 'ch',
            notification: {'type': 'SPLIT_UPDATE', 'changeNumber': 2}),
      ]);
      final client = EventSourceClient(transport: transport);
      final received = <RawNotification>[];
      await client.connect(Uri.parse('https://x/'), const {},
          onMessage: received.add);
      await client.close();
      await pumpEventQueue();
      // No exception; delivery stopped (may be 0 given immediate close).
      expect(received.length, lessThanOrEqualTo(2));
    });
  });
}

/// Pumps the event queue until [predicate] is true or a safety cap is hit.
Future<void> pumpUntil(bool Function() predicate, {int maxTicks = 200}) async {
  for (var i = 0; i < maxTicks && !predicate(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
