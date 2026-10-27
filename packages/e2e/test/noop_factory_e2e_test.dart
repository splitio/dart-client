// An invalid SDK key (empty or whitespace-only) MUST produce a NoOp factory
// (spec §7, §16) and MUST log an error stating the reason — previously the
// NoOp path was silent, so a misconfigured SDK key looked indistinguishable
// from a slow network from the outside.
//
// The NoOp client's `whenReady()` MUST NOT complete (so the invalid
// configuration surfaces as a startup failure instead of looking ready), and
// `whenTimeout()` MUST complete after `readyTimeout` (spec §8.2) — not
// instantly, and not never. Asserted via real HTTP interactions against a
// MockBackend (never against internal components) and via captured log
// output, on both the client-side and server-side flavors.
import 'dart:async';

import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

int _totalRequests(MockBackend backend) =>
    backend.splitChangesRequests.length +
    backend.streamingRequests.length +
    backend.authRequests.length +
    backend.impressionRequests.length +
    backend.eventRequests.length +
    backend.impressionsCountRequests.length +
    backend.uniqueKeysRequests.length +
    backend.uniqueKeysSsRequests.length +
    backend.segmentChangesRequests.length;

/// Runs [body] in a zone that captures everything printed (the SDK logger
/// writes via `print`) and returns the captured lines.
Future<List<String>> _captureLog(FutureOr<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    () async => await body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  group('NoOp factory on invalid SDK key — client-side', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    cs.SplitClientConfig config({int readyTimeout = 1}) {
      final baseUrl = _baseUrl(backend);
      return cs.SplitClientConfig(
        sync: cs.SyncConfig(
          serviceEndpoints: cs.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          readyTimeout: readyTimeout,
        ),
        logLevel: cs.LogLevel.error,
      );
    }

    for (final sdkKey in ['', '   ']) {
      final label = sdkKey.isEmpty ? 'empty' : 'whitespace-only';

      test('$label SDK key logs an error and returns a NoOp factory', () async {
        late cs.SplitFactory factory;
        final lines = await _captureLog(() {
          factory = cs.SplitFactory.create(
              sdkKey, config(), const cs.Key(matchingKey: 'user1'));
        });

        expect(lines.any((l) => l.contains('[ERROR]')), isTrue,
            reason: 'An invalid SDK key MUST log an error stating the '
                'reason. Captured lines: $lines');

        final client = factory.client();
        expect(client.getTreatment('any_flag'), equals('control'));

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(_totalRequests(backend), isZero,
            reason: 'A NoOp factory MUST NOT make any HTTP requests');

        await factory.destroy();
      });

      test('$label SDK key: whenReady() never completes', () async {
        final factory = cs.SplitFactory.create(
            sdkKey, config(readyTimeout: 1), const cs.Key(matchingKey: 'u'));
        final client = factory.client();

        await expectLater(
          client.whenReady().timeout(const Duration(seconds: 2)),
          throwsA(isA<TimeoutException>()),
          reason: "A NoOp client's whenReady() MUST NOT complete",
        );

        await factory.destroy();
      }, timeout: const Timeout(Duration(seconds: 10)));

      test('$label SDK key: whenTimeout() completes after readyTimeout',
          () async {
        final factory = cs.SplitFactory.create(
            sdkKey, config(readyTimeout: 1), const cs.Key(matchingKey: 'u'));
        final client = factory.client();

        await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 3)),
          completes,
          reason: "A NoOp client's whenTimeout() MUST complete after "
              'readyTimeout',
        );

        await factory.destroy();
      }, timeout: const Timeout(Duration(seconds: 10)));
    }

    test('destroy() before readyTimeout prevents whenTimeout from firing',
        () async {
      final factory = cs.SplitFactory.create(
          '', config(readyTimeout: 1), const cs.Key(matchingKey: 'u'));
      final client = factory.client();

      await factory.destroy();

      // Wait past the original readyTimeout window; whenTimeout() must
      // still not have completed.
      await expectLater(
        client.whenTimeout().timeout(const Duration(seconds: 2)),
        throwsA(isA<TimeoutException>()),
        reason: 'destroy() before readyTimeout MUST cancel the timer, so '
            'whenTimeout() never fires',
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  });

  group('NoOp factory on invalid SDK key — server-side', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    ss.SplitClientConfig config({int readyTimeout = 1}) {
      final baseUrl = _baseUrl(backend);
      return ss.SplitClientConfig(
        sync: ss.SyncConfig(
          serviceEndpoints: ss.ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
            authUrl: baseUrl,
            streamingUrl: baseUrl,
          ),
          readyTimeout: readyTimeout,
        ),
        installSignalHandler: false,
        logLevel: ss.LogLevel.error,
      );
    }

    for (final sdkKey in ['', '   ']) {
      final label = sdkKey.isEmpty ? 'empty' : 'whitespace-only';

      test('$label SDK key logs an error and returns a NoOp factory', () async {
        late ss.SplitFactory factory;
        final lines = await _captureLog(() {
          factory = ss.SplitFactory.create(sdkKey, config());
        });

        expect(lines.any((l) => l.contains('[ERROR]')), isTrue,
            reason: 'An invalid SDK key MUST log an error stating the '
                'reason. Captured lines: $lines');

        final client = factory.client();
        expect(client.getTreatment('user1', 'any_flag'), equals('control'));

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(_totalRequests(backend), isZero,
            reason: 'A NoOp factory MUST NOT make any HTTP requests');

        await factory.destroy();
      });

      test('$label SDK key: whenReady() never completes', () async {
        final factory = ss.SplitFactory.create(sdkKey, config(readyTimeout: 1));
        final client = factory.client();

        await expectLater(
          client.whenReady().timeout(const Duration(seconds: 2)),
          throwsA(isA<TimeoutException>()),
          reason: "A NoOp client's whenReady() MUST NOT complete",
        );

        await factory.destroy();
      }, timeout: const Timeout(Duration(seconds: 10)));

      test('$label SDK key: whenTimeout() completes after readyTimeout',
          () async {
        final factory = ss.SplitFactory.create(sdkKey, config(readyTimeout: 1));
        final client = factory.client();

        await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 3)),
          completes,
          reason: "A NoOp client's whenTimeout() MUST complete after "
              'readyTimeout',
        );

        await factory.destroy();
      }, timeout: const Timeout(Duration(seconds: 10)));
    }

    test('destroy() before readyTimeout prevents whenTimeout from firing',
        () async {
      final factory = ss.SplitFactory.create('', config(readyTimeout: 1));
      final client = factory.client();

      await factory.destroy();

      await expectLater(
        client.whenTimeout().timeout(const Duration(seconds: 2)),
        throwsA(isA<TimeoutException>()),
        reason: 'destroy() before readyTimeout MUST cancel the timer, so '
            'whenTimeout() never fires',
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
