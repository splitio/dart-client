import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/streaming/on_demand_fetch_coordinator.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// A recorded call to the fake fetch function.
class _FetchCall {
  final bool noCache;
  final int? till;
  _FetchCall(this.noCache, this.till);
}

/// Pumps the microtask queue so fire-and-forget `unawaited(_attempt())`
/// chains (which never go through a real Timer — only [FakeScheduler]
/// retries do) get a chance to run before assertions.
Future<void> _pump([int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('OnDemandFetchCoordinator', () {
    late FakeScheduler scheduler;
    late SplitLogger log;
    late int cursorValue;
    late List<_FetchCall> calls;
    late bool Function() fetchResult;

    OnDemandFetchCoordinator build() {
      return OnDemandFetchCoordinator(
        cursor: () => cursorValue,
        fetch: ({bool noCache = false, int? till}) async {
          calls.add(_FetchCall(noCache, till));
          return fetchResult();
        },
        scheduler: scheduler,
        logger: log,
        name: 'test',
      );
    }

    setUp(() {
      scheduler = FakeScheduler();
      log = SplitLogger(level: LogLevel.none);
      cursorValue = -1;
      calls = [];
      fetchResult = () => false;
    });

    test('ignores a changeNumber not newer than the cursor', () async {
      cursorValue = 100;
      final coordinator = build();

      coordinator.notify(100);
      await _pump();

      expect(calls, isEmpty);
      expect(scheduler.pendingCount, 0);
    });

    test('ignores a changeNumber not newer than one already being chased',
        () async {
      final coordinator = build();

      coordinator.notify(200);
      await _pump();
      final callsAfterFirst = calls.length;
      coordinator.notify(150); // older than the in-flight target (200)
      await _pump();

      expect(calls.length, callsAfterFirst);
    });

    test(
        'notify triggers an immediate fetch with noCache: true and no till '
        '(first attempt is never the bypass)', () async {
      final coordinator = build();

      coordinator.notify(200);
      await _pump();

      expect(calls, hasLength(1));
      expect(calls[0].noCache, isTrue);
      expect(calls[0].till, isNull);
      // Still behind -> a retry timer is scheduled.
      expect(scheduler.pendingCount, 1);
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 10000));
    });

    test('backoff progresses 10s -> 20s -> 40s -> 60s (capped)', () async {
      final coordinator = build();

      coordinator.notify(200);
      await _pump();
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 10000));

      scheduler.flush();
      await _pump();
      expect(calls, hasLength(2));
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 20000));

      scheduler.flush();
      await _pump();
      expect(calls, hasLength(3));
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 40000));

      scheduler.flush();
      await _pump();
      expect(calls, hasLength(4));
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 60000));

      scheduler.flush();
      await _pump();
      expect(calls, hasLength(5));
      // Capped — stays at 60s, does not keep doubling.
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 60000));
    });

    test(
        'after 10 backoff attempts, makes exactly one CDN-bypass fetch with '
        'till=<changeNumber>, then gives up (no further scheduling)', () async {
      final coordinator = build();

      coordinator.notify(200);
      await _pump();
      // Drive 9 more retries (10 normal attempts total: the immediate one +
      // 9 via backoff timers).
      for (var i = 0; i < 9; i++) {
        scheduler.flush();
        await _pump();
      }
      expect(calls, hasLength(10));
      expect(calls.every((c) => c.till == null), isTrue);
      // The 10th attempt's retry timer is pending; firing it makes the
      // bypass fetch.
      expect(scheduler.pendingCount, 1);

      scheduler.flush();
      await _pump();

      expect(calls, hasLength(11));
      expect(calls.last.noCache, isTrue);
      expect(calls.last.till, 200);
      // Gave up: nothing left scheduled.
      expect(scheduler.pendingCount, 0);
    });

    test('stops chasing once the cursor catches up (converges early)',
        () async {
      final coordinator = build();
      var callCount = 0;
      fetchResult = () {
        callCount++;
        if (callCount == 2) cursorValue = 200; // converge on the 2nd fetch
        return true;
      };

      coordinator.notify(200);
      await _pump();
      expect(calls, hasLength(1));
      expect(scheduler.pendingCount, 1);

      scheduler.flush();
      await _pump();

      expect(calls, hasLength(2));
      // Converged -> no further retry scheduled.
      expect(scheduler.pendingCount, 0);
    });

    test(
        'a newer notification while a retry timer is pending cancels it and '
        'restarts immediately with reset backoff', () async {
      final coordinator = build();

      coordinator.notify(100);
      await _pump();
      expect(calls, hasLength(1));
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 10000));

      coordinator.notify(300); // newer target, arrives while timer pending
      await _pump();

      // Restarted immediately: a 2nd fetch fired right away (not waiting
      // for the old timer).
      expect(calls, hasLength(2));
      // Backoff reset: the new pending retry is base delay again, not 20s.
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 10000));
    });

    test(
        'a newer notification while a fetch is in-flight is picked up when '
        'that fetch completes, re-targeting without counting it as a '
        'wasted attempt', () async {
      final completer = Completer<bool>();
      final coordinator = OnDemandFetchCoordinator(
        cursor: () => cursorValue,
        fetch: ({bool noCache = false, int? till}) {
          calls.add(_FetchCall(noCache, till));
          if (calls.length == 1) return completer.future;
          return Future.value(false);
        },
        scheduler: scheduler,
        logger: log,
        name: 'test',
      );

      coordinator.notify(100);
      await _pump();
      expect(calls, hasLength(1)); // in-flight, not yet resolved

      coordinator.notify(300); // newer target while the fetch is in-flight
      await _pump();
      // No second fetch fired yet — notify() doesn't preempt an in-flight
      // fetch; it just resets state for when it completes.
      expect(calls, hasLength(1));
      expect(scheduler.pendingCount, 0);

      completer.complete(false);
      await _pump();

      // Completion handler detected the target moved and re-attempted
      // immediately against the new target, with a fresh (not yet
      // incremented) backoff — i.e. retry delay is base, not doubled.
      expect(calls, hasLength(2));
      expect(
          scheduler.pendingDelays.single, const Duration(milliseconds: 10000));
    });

    test('dispose cancels any pending retry timer', () async {
      final coordinator = build();

      coordinator.notify(200);
      await _pump();
      expect(scheduler.pendingCount, 1);

      coordinator.dispose();

      expect(scheduler.pendingCount, 0);
    });

    test('dispose during an in-flight fetch schedules no further retry',
        () async {
      final inFlight = Completer<bool>();
      final coordinator = OnDemandFetchCoordinator(
        cursor: () => cursorValue,
        fetch: ({bool noCache = false, int? till}) {
          calls.add(_FetchCall(noCache, till));
          return inFlight.future;
        },
        scheduler: scheduler,
        logger: log,
        name: 'test',
      );

      coordinator.notify(200);
      await _pump();
      expect(calls, hasLength(1));

      coordinator.dispose();
      inFlight.complete(false);
      await _pump();

      expect(scheduler.pendingCount, 0);
      coordinator.notify(300);
      await _pump();
      expect(calls, hasLength(1));
    });

    test('a fetch exception is swallowed and still schedules a retry',
        () async {
      final coordinator = OnDemandFetchCoordinator(
        cursor: () => cursorValue,
        fetch: ({bool noCache = false, int? till}) async {
          calls.add(_FetchCall(noCache, till));
          throw Exception('boom');
        },
        scheduler: scheduler,
        logger: log,
        name: 'test',
      );

      coordinator.notify(200);
      await _pump();

      expect(calls, hasLength(1));
      expect(scheduler.pendingCount, 1);
    });
  });
}
