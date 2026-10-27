import 'dart:async';

import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/polling/polling_manager.dart';
import 'package:splitio_commons/src/sync/recorders/recorder.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_manager.dart';
import 'package:splitio_commons/src/sync/sync_manager.dart';
import 'package:test/test.dart';

/// Records every call so ordering can be asserted; flavor-free.
class _FakePolling implements PollingManager {
  final List<String> events;
  int syncAllCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  bool syncResult = true;
  bool _running = false;

  _FakePolling([List<String>? events]) : events = events ?? [];

  @override
  bool get isRunning => _running;

  @override
  Future<bool> syncAll() async {
    syncAllCalls++;
    events.add('polling.syncAll');
    return syncResult;
  }

  @override
  void start() {
    startCalls++;
    _running = true;
    events.add('polling.start');
  }

  @override
  void stop() {
    stopCalls++;
    _running = false;
    events.add('polling.stop');
  }
}

/// Fake [StreamingManager]: only start/stop are used by [SyncManager].
class _FakeStreaming implements StreamingManager {
  int startCalls = 0;
  int stopCalls = 0;

  /// Runs inside [stop] (after the call is recorded, before it completes),
  /// to simulate the push-down callback StreamingManager.stop() can emit.
  Future<void> Function()? duringStop;

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await duringStop?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRecorder implements Recorder {
  final String name;
  final List<String> events;
  int starts = 0;
  int stops = 0;
  int flushes = 0;
  bool _running = false;

  _FakeRecorder(this.name, this.events);

  // Recorder's stored fields aren't used by SyncManager's lifecycle methods;
  // stub them so `implements Recorder` compiles without real collaborators.
  @override
  SplitHttpClient get httpClient => throw UnimplementedError();
  @override
  SplitLogger get log => throw UnimplementedError();
  @override
  String get url => throw UnimplementedError();
  @override
  int get pushRateSeconds => throw UnimplementedError();

  @override
  bool get isRunning => _running;

  @override
  void start() {
    _running = true;
    starts++;
    events.add('$name.start');
  }

  @override
  void stop() {
    _running = false;
    stops++;
    events.add('$name.stop');
  }

  @override
  Future<void> flush() async {
    flushes++;
    events.add('$name.flush');
  }

  @override
  void clearRetained() {}
}

SyncManager _manager(
  _FakePolling polling, {
  StreamingManager? streaming,
  List<Recorder> recorders = const [],
}) =>
    SyncManager(
      polling: polling,
      logger: SplitLogger(level: LogLevel.none),
      recorders: recorders,
      streamingManager: streaming,
    );

void main() {
  group('SyncManager.initialSync', () {
    test('delegates to PollingManager.syncAll and returns its result',
        () async {
      final polling = _FakePolling()..syncResult = false;
      final sync = _manager(polling);

      expect(await sync.initialSync(), isFalse);
      expect(polling.syncAllCalls, 1);

      polling.syncResult = true;
      expect(await sync.initialSync(), isTrue);
      expect(polling.syncAllCalls, 2);
    });

    test('does not start polling (spec §8.1: polling follows initial sync)',
        () async {
      final polling = _FakePolling();
      final sync = _manager(polling);

      await sync.initialSync();

      expect(polling.startCalls, 0);
      expect(sync.isPolling, isFalse);
    });
  });

  group('SyncManager mode selection (§5.3)', () {
    test('startStreaming falls back to polling when no StreamingManager',
        () async {
      final polling = _FakePolling();
      final sync = _manager(polling);

      await sync.startStreaming();

      expect(polling.startCalls, 1);
      expect(sync.isPolling, isTrue);
      await sync.stop();
    });

    test('startStreaming with a StreamingManager starts it and does not poll',
        () async {
      final polling = _FakePolling();
      final streaming = _FakeStreaming();
      final sync = _manager(polling, streaming: streaming);

      await sync.startStreaming();

      expect(streaming.startCalls, 1);
      expect(polling.startCalls, 0);
      expect(sync.isPolling, isFalse);
    });

    test('stopStreaming stops streaming without touching polling', () async {
      final polling = _FakePolling();
      final streaming = _FakeStreaming();
      final sync = _manager(polling, streaming: streaming);
      sync.startPolling();

      await sync.stopStreaming();

      expect(streaming.stopCalls, 1);
      expect(polling.stopCalls, 0);
      expect(sync.isPolling, isTrue);
      await sync.stop();
    });

    test('stopStreaming without a StreamingManager is a no-op', () async {
      final sync = _manager(_FakePolling());
      await sync.stopStreaming();
    });

    test('startPolling is idempotent: repeated calls start the manager once',
        () {
      final polling = _FakePolling();
      final sync = _manager(polling);

      sync.startPolling();
      sync.startPolling();
      sync.startPolling();

      expect(polling.startCalls, 1,
          reason: 'repeated startPolling() MUST NOT re-arm running timers '
              '(spec §11.3: would starve them on a fast failure cadence)');
      expect(sync.isPolling, isTrue);
    });
  });

  group('SyncManager push/poll edges (§5.4)', () {
    test('onStreamingUp stops polling', () {
      final polling = _FakePolling();
      final sync = _manager(polling, streaming: _FakeStreaming());
      sync.startPolling();
      expect(sync.isPolling, isTrue);

      sync.onStreamingUp();

      expect(sync.isPolling, isFalse);
      expect(polling.stopCalls, 1);
    });

    test('onStreamingUp is safe to call repeatedly and while not polling', () {
      final sync = _manager(_FakePolling(), streaming: _FakeStreaming());
      sync.onStreamingUp();
      sync.onStreamingUp();
      expect(sync.isPolling, isFalse);
    });

    test('onStreamingDown (re)starts polling', () async {
      final polling = _FakePolling();
      final sync = _manager(polling, streaming: _FakeStreaming());
      expect(sync.isPolling, isFalse);

      sync.onStreamingDown();

      expect(sync.isPolling, isTrue);
      await sync.stop();
    });

    test('up -> down -> up cycle leaves consistent state', () async {
      final polling = _FakePolling();
      final sync = _manager(polling, streaming: _FakeStreaming());

      sync.onStreamingDown();
      expect(sync.isPolling, isTrue);
      sync.onStreamingUp();
      expect(sync.isPolling, isFalse);
      sync.onStreamingDown();
      sync.onStreamingDown();
      expect(sync.isPolling, isTrue);
      expect(polling.startCalls, 2,
          reason: 'one start per down edge after an up; repeated down is a '
              'no-op');
      sync.onStreamingUp();
      expect(sync.isPolling, isFalse);
      await sync.stop();
    });

    test('onStreamingDown does not duplicate an already-running poll', () {
      final polling = _FakePolling();
      final sync = _manager(polling);
      sync.startPolling();

      sync.onStreamingDown();

      expect(polling.startCalls, 1);
    });
  });

  group('SyncManager.stop (§5.5)', () {
    test('cancels polling and stops streaming; idempotent', () async {
      final polling = _FakePolling();
      final streaming = _FakeStreaming();
      final sync = _manager(polling, streaming: streaming);
      sync.startPolling();

      await sync.stop();
      await sync.stop();

      expect(sync.isPolling, isFalse);
      expect(streaming.stopCalls, 2);
    });

    test('returns an awaitable Future<void>', () async {
      final sync = _manager(_FakePolling());
      sync.startPolling();

      final result = sync.stop();
      expect(result, isA<Future<void>>());
      await result;

      expect(sync.isPolling, isFalse);
    });

    test('onStreamingDown and startPolling are no-ops once stopped', () async {
      final polling = _FakePolling();
      final sync = _manager(polling);
      sync.startPolling();
      await sync.stop();
      final startsAfterStop = polling.startCalls;

      sync.onStreamingDown();
      sync.startPolling();

      expect(sync.isPolling, isFalse,
          reason: 'a push-down callback or direct call MUST NOT resurrect '
              'polling after stop()');
      expect(polling.startCalls, startsAfterStop);
    });

    test('a push-down callback fired during streaming.stop() does not re-arm',
        () async {
      final polling = _FakePolling();
      final streaming = _FakeStreaming();
      final sync = _manager(polling, streaming: streaming);
      // StreamingManager.stop() while up emits NotifyPushDisabled, which
      // reaches onStreamingDown() mid-teardown.
      streaming.duringStop = () async {
        await Future<void>.delayed(Duration.zero);
        sync.onStreamingDown();
      };
      sync.onStreamingUp();

      await sync.stop();

      expect(sync.isPolling, isFalse);
      expect(polling.startCalls, 0,
          reason: 'stop() marks the manager stopped BEFORE awaiting '
              'streaming shutdown');
    });

    test('polling is cancelled both before and after the streaming await',
        () async {
      final events = <String>[];
      final polling = _FakePolling(events);
      final streaming = _FakeStreaming()
        ..duringStop = () async => events.add('streaming.stopping');
      final sync = _manager(polling, streaming: streaming);

      await sync.stop();

      expect(events, ['polling.stop', 'streaming.stopping', 'polling.stop']);
    });
  });

  group('SyncManager recorders (§5.8)', () {
    test('start / flush / stop reach every recorder, in list order', () async {
      final events = <String>[];
      final r1 = _FakeRecorder('r1', events);
      final r2 = _FakeRecorder('r2', events);
      final sync = _manager(_FakePolling(), recorders: [r1, r2]);

      sync.startRecorders();
      expect(events, ['r1.start', 'r2.start']);
      expect([r1.starts, r2.starts], [1, 1]);

      await sync.flushRecorders();
      expect([r1.flushes, r2.flushes], [1, 1]);

      await sync.stopRecorders();
      expect([r1.stops, r2.stops], [1, 1]);
      expect(events.sublist(events.length - 2), ['r1.stop', 'r2.stop']);
    });

    test('stop() does not touch recorders; flush after stop still works',
        () async {
      final events = <String>[];
      final r = _FakeRecorder('r', events);
      final sync = _manager(_FakePolling(events), recorders: [r]);
      sync.startRecorders();

      await sync.stop();
      expect(r.stops, 0);

      // Factory teardown (spec §8.5): stop sync, then the final flush, then
      // stopRecorders.
      await sync.flushRecorders();
      await sync.stopRecorders();
      expect(events, [
        'r.start',
        'polling.stop',
        'polling.stop',
        'r.flush',
        'r.stop',
      ]);
    });

    test('no recorders: lifecycle calls are harmless', () async {
      final sync = _manager(_FakePolling());
      sync.startRecorders();
      await sync.flushRecorders();
      await sync.stopRecorders();
    });
  });
}
