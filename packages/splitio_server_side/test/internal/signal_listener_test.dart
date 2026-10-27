import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/log_level.dart';
import 'package:splitio_server_side/src/internal/signal_listener.dart';
import 'package:test/test.dart';

void main() {
  group('SignalListener.install', () {
    test('invokes onSignal exactly once on first signal, then calls exitFn(0)',
        () async {
      final controller = StreamController<int>();
      var onSignalCalls = 0;
      int? exitCode;
      final listener = SignalListener(
        signals: [controller.stream],
        onSignal: () async {
          onSignalCalls++;
        },
        exitFn: (code) {
          exitCode = code;
        },
        logger: SplitLogger(level: LogLevel.error),
      );
      listener.install();
      controller.add(15);
      controller.add(2);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(onSignalCalls, equals(1));
      expect(exitCode, equals(0));
      await listener.dispose();
      await controller.close();
    });

    test('dispose cancels the subscription so subsequent signals are ignored',
        () async {
      final controller = StreamController<int>();
      var onSignalCalls = 0;
      final listener = SignalListener(
        signals: [controller.stream],
        onSignal: () async {
          onSignalCalls++;
        },
        exitFn: (_) {},
        logger: SplitLogger(level: LogLevel.error),
      );
      listener.install();
      await listener.dispose();
      controller.add(15);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(onSignalCalls, equals(0));
      await controller.close();
    });

    test('dispose cancels the subscription on every signal source', () async {
      var cancelled = 0;
      final sigterm = StreamController<int>(onCancel: () => cancelled++);
      final sigint = StreamController<int>(onCancel: () => cancelled++);
      final listener = SignalListener(
        signals: [sigterm.stream, sigint.stream],
        onSignal: () async {},
        exitFn: (_) {},
        logger: SplitLogger(level: LogLevel.error),
      );
      listener.install();
      await listener.dispose();
      expect(cancelled, equals(2));
      await sigterm.close();
      await sigint.close();
    });

    test('a signal on any source triggers onSignal and releases all sources',
        () async {
      var cancelled = 0;
      final sigterm = StreamController<int>(onCancel: () => cancelled++);
      final sigint = StreamController<int>(onCancel: () => cancelled++);
      var onSignalCalls = 0;
      int? exitCode;
      final listener = SignalListener(
        signals: [sigterm.stream, sigint.stream],
        onSignal: () async {
          onSignalCalls++;
        },
        exitFn: (code) {
          exitCode = code;
        },
        logger: SplitLogger(level: LogLevel.error),
      );
      listener.install();
      sigint.add(2);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(onSignalCalls, equals(1));
      expect(exitCode, equals(0));
      expect(cancelled, equals(2));
      await sigterm.close();
      await sigint.close();
    });

    test('dispose is idempotent', () async {
      final controller = StreamController<int>();
      final listener = SignalListener(
        signals: [controller.stream],
        onSignal: () async {},
        exitFn: (_) {},
        logger: SplitLogger(level: LogLevel.error),
      );
      listener.install();
      await listener.dispose();
      await listener.dispose();
      await controller.close();
    });
  });
}
