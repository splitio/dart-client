import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/recorders/recorder.dart';
import 'package:splitio_commons/src/sync/recorders/telemetry_recorder.dart';
import 'package:test/test.dart';

void main() {
  group('TelemetryRecorder', () {
    late List<http.Request> capturedRequests;

    TelemetryRecorder makeRecorder() {
      capturedRequests = [];
      final client = SplitHttpClient(
        apiKey: 'test-api-key',
        client: MockClient((req) async {
          capturedRequests.add(req);
          return http.Response('', 200);
        }),
      );
      return TelemetryRecorder(
        httpClient: client,
        url: 'https://telemetry.split.io/api',
        log: SplitLogger(level: LogLevel.none),
      );
    }

    test('is a Recorder', () {
      expect(makeRecorder(), isA<Recorder>());
    });

    test('flush is a no-op in v1 — no HTTP calls are made', () async {
      final recorder = makeRecorder();

      await recorder.flush();

      expect(capturedRequests, isEmpty);
    });

    test('start()/stop() do not throw and do not trigger flush HTTP calls',
        () async {
      final recorder = makeRecorder();

      recorder.start();
      expect(recorder.isRunning, isTrue);
      recorder.stop();
      expect(recorder.isRunning, isFalse);

      expect(capturedRequests, isEmpty);
    });
  });
}
