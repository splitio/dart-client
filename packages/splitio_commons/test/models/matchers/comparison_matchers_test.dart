import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('GreaterThanOrEqualToMatcher', () {
    group('number dataType', () {
      const matcher =
          GreaterThanOrEqualToMatcher(value: 18, dataType: DataType.number);

      test('matches equal int', () {
        expect(matcher.match(18, defaultCtx()), isTrue);
      });

      test('matches greater int', () {
        expect(matcher.match(19, defaultCtx()), isTrue);
      });

      test('does not match lesser int', () {
        expect(matcher.match(17, defaultCtx()), isFalse);
      });

      test('a fractional double >= configured int matches (18.5 >= 18)', () {
        expect(matcher.match(18.5, defaultCtx()), isTrue);
      });

      test('a lesser double does not match', () {
        expect(matcher.match(17.9, defaultCtx()), isFalse);
      });

      test('returns false for non-numeric values', () {
        expect(matcher.match(null, defaultCtx()), isFalse);
        expect(matcher.match('18', defaultCtx()), isFalse);
      });
    });

    group('datetime dataType', () {
      final threshold = DateTime.utc(2024, 1, 15, 9, 0).millisecondsSinceEpoch;
      final matcher = GreaterThanOrEqualToMatcher(
          value: threshold, dataType: DataType.datetime);

      test('matches a double of epoch millis at or after the threshold', () {
        final after =
            DateTime.utc(2024, 1, 15, 10, 0).millisecondsSinceEpoch.toDouble();
        expect(matcher.match(after, defaultCtx()), isTrue);
      });

      test('does not match a double before the threshold', () {
        final before =
            DateTime.utc(2024, 1, 15, 8, 0).millisecondsSinceEpoch.toDouble();
        expect(matcher.match(before, defaultCtx()), isFalse);
      });
    });
  });

  group('LessThanOrEqualToMatcher', () {
    group('number dataType', () {
      const matcher =
          LessThanOrEqualToMatcher(value: 65, dataType: DataType.number);

      test('matches equal int', () {
        expect(matcher.match(65, defaultCtx()), isTrue);
      });

      test('matches lesser int', () {
        expect(matcher.match(64, defaultCtx()), isTrue);
      });

      test('does not match greater int', () {
        expect(matcher.match(66, defaultCtx()), isFalse);
      });

      test('a fractional double <= configured int matches (64.5 <= 65)', () {
        expect(matcher.match(64.5, defaultCtx()), isTrue);
      });

      test('a greater double does not match', () {
        expect(matcher.match(65.1, defaultCtx()), isFalse);
      });

      test('returns false for non-numeric values', () {
        expect(matcher.match(null, defaultCtx()), isFalse);
        expect(matcher.match('65', defaultCtx()), isFalse);
      });
    });

    group('datetime dataType', () {
      final threshold = DateTime.utc(2024, 1, 15, 17, 0).millisecondsSinceEpoch;
      final matcher = LessThanOrEqualToMatcher(
          value: threshold, dataType: DataType.datetime);

      test('matches a double of epoch millis at or before the threshold', () {
        final before =
            DateTime.utc(2024, 1, 15, 16, 0).millisecondsSinceEpoch.toDouble();
        expect(matcher.match(before, defaultCtx()), isTrue);
      });

      test('does not match a double after the threshold', () {
        final after =
            DateTime.utc(2024, 1, 15, 18, 0).millisecondsSinceEpoch.toDouble();
        expect(matcher.match(after, defaultCtx()), isFalse);
      });
    });
  });
}
