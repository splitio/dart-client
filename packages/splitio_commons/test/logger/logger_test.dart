import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:test/test.dart';

/// Captures print output within [body] and returns the printed lines.
List<String> captureOutput(void Function() body) {
  final lines = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        lines.add(line);
      },
    ),
  );
  return lines;
}

void main() {
  group('SplitLogger', () {
    test('default level is info', () {
      final logger = SplitLogger();
      final output = captureOutput(() {
        logger.info('hello');
      });
      expect(output, hasLength(1));
      expect(output.first, contains('[INFO]'));
    });

    test('prints messages at the configured level', () {
      final logger = SplitLogger(level: LogLevel.warning);
      final output = captureOutput(() {
        logger.warning('a warning');
      });
      expect(output, hasLength(1));
      expect(output.first, equals('[Split][WARNING] a warning'));
    });

    test('prints messages above the configured level', () {
      final logger = SplitLogger(level: LogLevel.info);
      final output = captureOutput(() {
        logger.warning('warn msg');
        logger.error('err msg');
      });
      expect(output, hasLength(2));
      expect(output[0], contains('[WARNING]'));
      expect(output[1], contains('[ERROR]'));
    });

    test('suppresses messages below the configured level', () {
      final logger = SplitLogger(level: LogLevel.warning);
      final output = captureOutput(() {
        logger.verbose('v');
        logger.debug('d');
        logger.info('i');
      });
      expect(output, isEmpty);
    });

    test('LogLevel.none suppresses all messages', () {
      final logger = SplitLogger(level: LogLevel.none);
      final output = captureOutput(() {
        logger.verbose('v');
        logger.debug('d');
        logger.info('i');
        logger.warning('w');
        logger.error('e');
      });
      expect(output, isEmpty);
    });

    test('error with error object appends it to the message', () {
      final logger = SplitLogger(level: LogLevel.error);
      final output = captureOutput(() {
        logger.error('something failed', Exception('boom'));
      });
      expect(output, hasLength(1));
      expect(output.first,
          equals('[Split][ERROR] something failed: Exception: boom'));
    });

    test('error without error object prints only the message', () {
      final logger = SplitLogger(level: LogLevel.error);
      final output = captureOutput(() {
        logger.error('plain error');
      });
      expect(output, hasLength(1));
      expect(output.first, equals('[Split][ERROR] plain error'));
    });

    test('verbose level prints all messages', () {
      final logger = SplitLogger(level: LogLevel.verbose);
      final output = captureOutput(() {
        logger.verbose('v');
        logger.debug('d');
        logger.info('i');
        logger.warning('w');
        logger.error('e');
      });
      expect(output, hasLength(5));
    });
  });
}
