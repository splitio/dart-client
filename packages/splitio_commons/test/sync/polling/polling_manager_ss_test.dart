import 'dart:async';

import 'package:splitio_commons/src/sync/polling/polling_manager_ss.dart';
import 'package:test/test.dart';

class _FakeFetch {
  int calls = 0;
  bool nextResult = true;
  Future<bool> fetch() async {
    calls++;
    return nextResult;
  }
}

PollingManagerSS _polling({
  required _FakeFetch flags,
  required _FakeFetch segments,
  Duration features = const Duration(seconds: 60),
  Duration segs = const Duration(seconds: 60),
}) =>
    PollingManagerSS(
      fetchFlags: flags.fetch,
      fetchSegments: segments.fetch,
      featuresRefreshRate: features,
      segmentsRefreshRate: segs,
    );

void main() {
  group('PollingManagerSS.syncAll', () {
    test('returns true when both fetches succeed', () async {
      final flags = _FakeFetch();
      final segments = _FakeFetch();
      final ok = await _polling(flags: flags, segments: segments).syncAll();
      expect(ok, isTrue);
      expect(flags.calls, 1);
      expect(segments.calls, 1);
    });

    test('flags first, segments second', () async {
      final order = <String>[];
      final mgr = PollingManagerSS(
        fetchFlags: () async {
          order.add('flags');
          return true;
        },
        fetchSegments: () async {
          order.add('segments');
          return true;
        },
        featuresRefreshRate: const Duration(seconds: 60),
        segmentsRefreshRate: const Duration(seconds: 60),
      );
      await mgr.syncAll();
      expect(order, ['flags', 'segments']);
    });

    test('returns false when flags fetch fails, still fetches segments',
        () async {
      final flags = _FakeFetch()..nextResult = false;
      final segments = _FakeFetch();
      final ok = await _polling(flags: flags, segments: segments).syncAll();
      expect(ok, isFalse);
      expect(segments.calls, 1, reason: 'no short-circuit');
    });

    test('returns false when segments fetch fails', () async {
      final flags = _FakeFetch();
      final segments = _FakeFetch()..nextResult = false;
      final ok = await _polling(flags: flags, segments: segments).syncAll();
      expect(ok, isFalse);
    });
  });

  group('PollingManagerSS timers', () {
    test('isRunning is false before start, true after, false after stop', () {
      final mgr = _polling(flags: _FakeFetch(), segments: _FakeFetch());
      expect(mgr.isRunning, isFalse);
      mgr.start();
      expect(mgr.isRunning, isTrue);
      mgr.stop();
      expect(mgr.isRunning, isFalse);
    });

    test('stop is idempotent, including before start', () {
      final mgr = _polling(flags: _FakeFetch(), segments: _FakeFetch());
      mgr.stop();
      mgr.start();
      mgr.stop();
      mgr.stop();
      expect(mgr.isRunning, isFalse);
    });

    test('timers fire at their own rates', () async {
      final flags = _FakeFetch();
      final segments = _FakeFetch();
      final mgr = _polling(
        flags: flags,
        segments: segments,
        features: const Duration(milliseconds: 50),
        segs: const Duration(seconds: 60),
      );
      mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      mgr.stop();
      expect(flags.calls, greaterThan(0));
      expect(segments.calls, 0);

      final seen = flags.calls;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(flags.calls, seen, reason: 'no fires after stop');
    });

    test('segments timer fires at the segments rate', () async {
      final flags = _FakeFetch();
      final segments = _FakeFetch();
      final mgr = _polling(
        flags: flags,
        segments: segments,
        features: const Duration(seconds: 60),
        segs: const Duration(milliseconds: 50),
      );
      mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      mgr.stop();
      expect(segments.calls, greaterThan(0));
      expect(flags.calls, 0);
    });

    // Regression (§11.3): repeated start() calls faster than the refresh
    // rate must not reset the running timer, or it never fires.
    test('repeated start does not reset the running flags timer (regression)',
        () async {
      final flags = _FakeFetch();
      final mgr = _polling(
        flags: flags,
        segments: _FakeFetch(),
        features: const Duration(seconds: 1),
        segs: const Duration(seconds: 9999),
      );
      for (var i = 0; i < 6; i++) {
        mgr.start();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(flags.calls, greaterThan(0),
          reason: 'The flags timer created on the first start() MUST survive '
              'later no-op calls and fire at its original 1s period');
      mgr.stop();
    });
  });
}
