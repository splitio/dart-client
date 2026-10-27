import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/recorders/batch_submitter.dart';
import 'package:test/test.dart';

SplitHttpResponse _response(int statusCode) =>
    SplitHttpResponse(statusCode: statusCode, body: '', headers: const {});

void main() {
  group('BatchSubmitter', () {
    late List<String> warnings;
    late SplitLogger log;

    setUp(() {
      warnings = [];
      log = _CapturingLogger(warnings);
    });

    test('submit does nothing for an empty batch', () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      var called = false;
      await submitter.submit([], () async {
        called = true;
        return _response(200);
      });
      expect(called, isFalse);
    });

    test('a 2xx response does not retain anything for next cycle', () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1, 2], () async => _response(200));

      // Nothing retained: prependRetained returns fresh items unchanged.
      expect(submitter.prependRetained([3]), [3]);
    });

    test('a transient (5xx) failure retains the batch for the next cycle',
        () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1, 2], () async => _response(500));

      expect(submitter.prependRetained([3]), [1, 2, 3]);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('things'));
      expect(warnings.first, contains('2'));
    });

    test('a 429 failure retains the batch for the next cycle', () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1], () async => _response(429));

      expect(submitter.prependRetained([]), [1]);
    });

    test('a transport error (thrown exception) retains the batch', () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1], () async => throw Exception('boom'));

      expect(submitter.prependRetained([]), [1]);
      expect(warnings.first, contains('Retaining for retry'));
    });

    test('two chunks failing in the same cycle are both retained', () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1, 2], () async => _response(500));
      await submitter.submit([3], () async => _response(503));

      expect(submitter.prependRetained([4]), [1, 2, 3, 4]);
    });

    test('a retained batch that fails again is dropped, not retained again',
        () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1, 2], () async => _response(500));

      final merged = submitter.prependRetained([3]);
      expect(merged, [1, 2, 3]);

      await submitter.submit(merged, () async => _response(500));

      // Dropped: nothing retained for the following cycle.
      expect(submitter.prependRetained([4]), [4]);
      expect(warnings, hasLength(2));
      expect(warnings[1], contains('Dropping things batch'));
      expect(warnings[1], contains('3'));
    });

    test('a retained batch that succeeds on retry clears retry state',
        () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1], () async => _response(500));

      final merged = submitter.prependRetained([2]);
      await submitter.submit(merged, () async => _response(200));

      // Succeeded: nothing retained, and the NEXT failure is treated as a
      // fresh (non-retry) failure again (gets one retry chance).
      expect(submitter.prependRetained([3]), [3]);
      await submitter.submit([3], () async => _response(500));
      expect(submitter.prependRetained([]), [3]);
    });

    test('a non-retryable 4xx drops the batch immediately, no retry', () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1, 2], () async => _response(400));

      expect(submitter.prependRetained([3]), [3]);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('Dropping things batch'));
    });

    test('clear() drops a retained batch — nothing is prepended afterwards',
        () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1, 2], () async => _response(500));

      submitter.clear();

      expect(submitter.prependRetained([3]), [3]);
    });

    test(
        'clear() resets retry status — the next failure gets a fresh retry '
        'chance, not an immediate drop', () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      await submitter.submit([1], () async => _response(500));

      submitter.clear();

      // If clear() had not reset _cycleIsRetry, this failure would be
      // treated as a retry's second failure and dropped immediately.
      await submitter.submit([2], () async => _response(500));
      expect(submitter.prependRetained([3]), [2, 3]);
    });

    test('clear() on a submitter with nothing retained is a no-op', () async {
      final submitter = BatchSubmitter<int>(log: log, dataTypeName: 'things');
      submitter.clear();
      expect(submitter.prependRetained([1]), [1]);
    });
  });
}

class _CapturingLogger extends SplitLogger {
  final List<String> warnings;
  _CapturingLogger(this.warnings) : super(level: LogLevel.none);

  @override
  void warning(String message) => warnings.add(message);
}
