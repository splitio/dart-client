import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('BetweenMatcher', () {
    group('number dataType', () {
      const matcher =
          BetweenMatcher(start: 10, end: 20, dataType: DataType.number);

      test('matches value at start boundary', () {
        expect(matcher.match(10, defaultCtx()), isTrue);
      });

      test('matches value at end boundary', () {
        expect(matcher.match(20, defaultCtx()), isTrue);
      });

      test('matches value in range', () {
        expect(matcher.match(15, defaultCtx()), isTrue);
      });

      test('does not match value below start', () {
        expect(matcher.match(9, defaultCtx()), isFalse);
        expect(matcher.match(0, defaultCtx()), isFalse);
      });

      test('does not match value above end', () {
        expect(matcher.match(21, defaultCtx()), isFalse);
        expect(matcher.match(100, defaultCtx()), isFalse);
      });

      test('returns false for non-numeric values', () {
        expect(matcher.match(null, defaultCtx()), isFalse);
        expect(matcher.match('not a number', defaultCtx()), isFalse);
        expect(matcher.match(true, defaultCtx()), isFalse);
      });

      test('handles negative ranges', () {
        const negativeMatcher =
            BetweenMatcher(start: -20, end: -10, dataType: DataType.number);
        expect(negativeMatcher.match(-15, defaultCtx()), isTrue);
        expect(negativeMatcher.match(-20, defaultCtx()), isTrue);
        expect(negativeMatcher.match(-10, defaultCtx()), isTrue);
        expect(negativeMatcher.match(-5, defaultCtx()), isFalse);
        expect(negativeMatcher.match(-25, defaultCtx()), isFalse);
      });
    });

    group('datetime dataType', () {
      // asDateHourMinute uses milliseconds and truncates to minute
      final start = DateTime.utc(2024, 1, 15, 9, 0).millisecondsSinceEpoch;
      final end = DateTime.utc(2024, 1, 15, 17, 0).millisecondsSinceEpoch;
      final matcher =
          BetweenMatcher(start: start, end: end, dataType: DataType.datetime);

      test('matches time in range', () {
        expect(matcher.match(start, defaultCtx()), isTrue);
        final noon = DateTime.utc(2024, 1, 15, 12, 0).millisecondsSinceEpoch;
        expect(matcher.match(noon, defaultCtx()), isTrue);
        expect(matcher.match(end, defaultCtx()), isTrue);
      });

      test('does not match time outside range', () {
        final before = DateTime.utc(2024, 1, 15, 8, 0).millisecondsSinceEpoch;
        expect(matcher.match(before, defaultCtx()), isFalse);
        final after = DateTime.utc(2024, 1, 15, 18, 0).millisecondsSinceEpoch;
        expect(matcher.match(after, defaultCtx()), isFalse);
      });

      test('returns false for invalid datetime values', () {
        expect(matcher.match(null, defaultCtx()), isFalse);
        expect(matcher.match('invalid', defaultCtx()), isFalse);
      });
    });
  });
}
