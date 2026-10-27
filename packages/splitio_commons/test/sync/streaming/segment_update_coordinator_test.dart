import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/streaming/segment_update_coordinator.dart';
import 'package:test/test.dart';

import 'fakes.dart';

Future<void> _pump([int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('SegmentUpdateCoordinator', () {
    late FakeScheduler scheduler;
    late SplitLogger log;
    late Map<String, int> cursors;
    late List<(String, bool, int?)> calls;

    SegmentUpdateCoordinator build() {
      return SegmentUpdateCoordinator(
        fetcher: (name, {bool noCache = false, int? till}) async {
          calls.add((name, noCache, till));
          return true;
        },
        cursor: (name) => cursors[name] ?? -1,
        scheduler: scheduler,
        logger: log,
      );
    }

    setUp(() {
      scheduler = FakeScheduler();
      log = SplitLogger(level: LogLevel.none);
      cursors = {};
      calls = [];
    });

    test('lazily creates one coordinator per segment name on first notify',
        () async {
      final coordinator = build();

      coordinator.notify('seg_a', 100);
      await _pump();

      expect(calls, hasLength(1));
      expect(calls.single.$1, 'seg_a');
      expect(calls.single.$2, isTrue); // noCache
      expect(calls.single.$3, isNull); // till
    });

    test(
        'notifying one segment does not affect another segment\'s chase '
        'state (independent cursors)', () async {
      final coordinator = SegmentUpdateCoordinator(
        fetcher: (name, {bool noCache = false, int? till}) async {
          calls.add((name, noCache, till));
          // seg_b converges on its very first fetch; seg_a never does.
          if (name == 'seg_b') cursors['seg_b'] = 50;
          return true;
        },
        cursor: (name) => cursors[name] ?? -1,
        scheduler: scheduler,
        logger: log,
      );

      // seg_a never converges -> keeps retrying.
      coordinator.notify('seg_a', 100);
      await _pump();
      coordinator.notify('seg_b', 50);
      await _pump();

      // seg_a scheduled a retry; seg_b converged and did not.
      expect(scheduler.pendingCount, 1);

      scheduler.flush(); // only fires seg_a's pending timer
      await _pump();

      final segACalls = calls.where((c) => c.$1 == 'seg_a').length;
      final segBCalls = calls.where((c) => c.$1 == 'seg_b').length;
      expect(segACalls, greaterThanOrEqualTo(2)); // kept retrying
      expect(segBCalls, 1); // single call, no retry scheduled for seg_b
    });

    test('dispose cancels every tracked segment\'s pending timer', () async {
      final coordinator = build();

      coordinator.notify('seg_a', 100);
      coordinator.notify('seg_b', 200);
      await _pump();
      expect(scheduler.pendingCount, 2);

      coordinator.dispose();

      expect(scheduler.pendingCount, 0);
    });

    test(
        'a later, higher changeNumber for the same segment restarts its '
        'own chase without touching other segments', () async {
      final coordinator = build();

      coordinator.notify('seg_a', 100);
      await _pump();
      final callsAfterFirst = calls.length;

      coordinator.notify('seg_a', 300);
      await _pump();

      expect(calls.length, greaterThan(callsAfterFirst));
      expect(calls.every((c) => c.$1 == 'seg_a'), isTrue);
    });
  });
}
