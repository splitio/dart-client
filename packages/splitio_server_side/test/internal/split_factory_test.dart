import 'dart:async';

import 'package:splitio_commons/src/models/config.dart';
import 'package:splitio_server_side/src/internal/split_factory.dart';
import 'package:test/test.dart';

void main() {
  group('SplitFactory.create', () {
    test('returns a working factory for a non-empty sdkKey', () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(installSignalHandler: false));
      // client() returns the same instance twice.
      final c1 = f.client();
      final c2 = f.client();
      expect(identical(c1, c2), isTrue);
      await f.destroy();
    });

    test('empty sdkKey returns a NoOp factory that never touches the network',
        () async {
      final f = SplitFactory.create(
          '', const SplitClientConfig(installSignalHandler: false));
      final c = f.client();
      expect(c.getTreatment('user', 'flag'), equals('control'));
      expect(c.track('user', 'user', 'ev'), isFalse);
      await f.destroy();
    });

    test(
        'whitespace-only sdkKey returns a NoOp factory that never touches '
        'the network', () async {
      final f = SplitFactory.create(
          '   ', const SplitClientConfig(installSignalHandler: false));
      final c = f.client();
      expect(c.getTreatment('user', 'flag'), equals('control'));
      expect(c.track('user', 'user', 'ev'), isFalse);
      await f.destroy();
    });

    test('destroy is idempotent', () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(installSignalHandler: false));
      await f.destroy();
      await f.destroy();
    });
  });

  group('SplitFactory NoOp — whenX on invalid factory', () {
    test('NoOp client whenReady() never completes', () async {
      final f = SplitFactory.create(
          '', const SplitClientConfig(installSignalHandler: false));
      final client = f.client();
      await expectLater(
          client.whenReady().timeout(const Duration(milliseconds: 200)),
          throwsA(isA<TimeoutException>()),
          reason: "A NoOp client's whenReady() MUST NOT complete (spec §7)");
      await f.destroy();
    });

    test('NoOp client whenTimeout() completes after readyTimeout', () async {
      final f = SplitFactory.create(
          '',
          const SplitClientConfig(
              installSignalHandler: false, sync: SyncConfig(readyTimeout: 1)));
      final client = f.client();
      await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 3)), completes,
          reason: "A NoOp client's whenTimeout() MUST complete after "
              'readyTimeout (spec §7, §8.2)');
      await f.destroy();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
        'NoOp factory destroy() before readyTimeout prevents whenTimeout '
        'from firing', () async {
      final f = SplitFactory.create(
          '',
          const SplitClientConfig(
              installSignalHandler: false, sync: SyncConfig(readyTimeout: 1)));
      final client = f.client();
      await f.destroy();
      await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 2)),
          throwsA(isA<TimeoutException>()),
          reason: 'destroy() before readyTimeout MUST cancel the timer');
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
