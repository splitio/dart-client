import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('EqualToMatcher', () {
    group('number dataType', () {
      const matcher = EqualToMatcher(value: 42, dataType: DataType.number);

      test('matches equal integer', () {
        expect(matcher.match(42, defaultCtx()), isTrue);
      });

      test('does not match string representation', () {
        // asLong only accepts int, not String
        expect(matcher.match('42', defaultCtx()), isFalse);
      });

      test('does not match different number', () {
        expect(matcher.match(41, defaultCtx()), isFalse);
        expect(matcher.match(0, defaultCtx()), isFalse);
      });

      test('returns false for non-numeric values', () {
        expect(matcher.match(null, defaultCtx()), isFalse);
        expect(matcher.match('not a number', defaultCtx()), isFalse);
        expect(matcher.match(true, defaultCtx()), isFalse);
        expect(matcher.match(<String>[], defaultCtx()), isFalse);
      });

      test('handles negative numbers', () {
        const negativeMatcher =
            EqualToMatcher(value: -10, dataType: DataType.number);
        expect(negativeMatcher.match(-10, defaultCtx()), isTrue);
        expect(negativeMatcher.match(10, defaultCtx()), isFalse);
      });
    });

    group('datetime dataType', () {
      // asDate works with epoch milliseconds and truncates to day
      final timestamp = DateTime.utc(2024, 1, 15).millisecondsSinceEpoch;
      final matcher =
          EqualToMatcher(value: timestamp, dataType: DataType.datetime);

      test('matches equal datetime', () {
        expect(matcher.match(timestamp, defaultCtx()), isTrue);
        // Also matches same day with different time (truncates to day)
        final sameDay =
            DateTime.utc(2024, 1, 15, 14, 30).millisecondsSinceEpoch;
        expect(matcher.match(sameDay, defaultCtx()), isTrue);
      });

      test('does not match different datetime', () {
        final differentTimestamp =
            DateTime.utc(2024, 1, 16).millisecondsSinceEpoch;
        expect(matcher.match(differentTimestamp, defaultCtx()), isFalse);
      });

      test('returns false for invalid datetime values', () {
        expect(matcher.match(null, defaultCtx()), isFalse);
        expect(matcher.match('not a date', defaultCtx()), isFalse);
      });
    });
  });
}
