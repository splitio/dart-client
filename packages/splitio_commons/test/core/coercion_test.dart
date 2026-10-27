import 'package:splitio_commons/src/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Coercion', () {
    group('asNumber', () {
      test('int value passes through', () {
        expect(asNumber(42), equals(42));
        expect(asNumber(0), equals(0));
        expect(asNumber(-1), equals(-1));
      });

      test('double value passes through unchanged', () {
        expect(asNumber(18.5), equals(18.5));
        expect(asNumber(-3.25), equals(-3.25));
        expect(asNumber(18.0), equals(18.0));
      });

      test('non-finite double returns null', () {
        expect(asNumber(double.nan), isNull);
        expect(asNumber(double.infinity), isNull);
        expect(asNumber(double.negativeInfinity), isNull);
      });

      test('non-numeric returns null', () {
        expect(asNumber('42'), isNull);
        expect(asNumber('18.5'), isNull);
        expect(asNumber(null), isNull);
        expect(asNumber(true), isNull);
        expect(asNumber([1]), isNull);
      });
    });

    group('asBoolean', () {
      test('bool value passes through', () {
        expect(asBoolean(true), isTrue);
        expect(asBoolean(false), isFalse);
      });

      test('string "true"/"false" (case insensitive)', () {
        expect(asBoolean('true'), isTrue);
        expect(asBoolean('TRUE'), isTrue);
        expect(asBoolean('True'), isTrue);
        expect(asBoolean('false'), isFalse);
        expect(asBoolean('FALSE'), isFalse);
        expect(asBoolean('False'), isFalse);
      });

      test('other values return null', () {
        expect(asBoolean('yes'), isNull);
        expect(asBoolean(1), isNull);
        expect(asBoolean(null), isNull);
        expect(asBoolean(''), isNull);
      });
    });

    group('asDate', () {
      test('truncates to day in UTC', () {
        // 2023-06-15 14:30:00 UTC -> 2023-06-15 00:00:00 UTC
        final input =
            DateTime.utc(2023, 6, 15, 14, 30, 45).millisecondsSinceEpoch;
        final expected = DateTime.utc(2023, 6, 15).millisecondsSinceEpoch;
        expect(asDate(input), equals(expected));
      });

      test('midnight stays midnight', () {
        final input = DateTime.utc(2023, 1, 1).millisecondsSinceEpoch;
        expect(asDate(input), equals(input));
      });

      test('accepts a double of epoch millis, truncated toward zero', () {
        final day = DateTime.utc(2023, 6, 15).millisecondsSinceEpoch;
        final input = DateTime.utc(2023, 6, 15, 14, 30, 45)
            .millisecondsSinceEpoch
            .toDouble();
        expect(asDate(input), equals(day));
      });

      test('non-numeric returns null', () {
        expect(asDate('12345'), isNull);
        expect(asDate(null), isNull);
      });
    });

    group('asDateHourMinute', () {
      test('truncates to minute in UTC', () {
        // 2023-06-15 14:30:45 UTC -> 2023-06-15 14:30:00 UTC
        final input =
            DateTime.utc(2023, 6, 15, 14, 30, 45).millisecondsSinceEpoch;
        final expected =
            DateTime.utc(2023, 6, 15, 14, 30).millisecondsSinceEpoch;
        expect(asDateHourMinute(input), equals(expected));
      });

      test('exact minute stays same', () {
        final input = DateTime.utc(2023, 3, 10, 8, 0).millisecondsSinceEpoch;
        expect(asDateHourMinute(input), equals(input));
      });

      test('accepts a double of epoch millis, truncated toward zero', () {
        final minute = DateTime.utc(2023, 3, 10, 8, 15).millisecondsSinceEpoch;
        final input = DateTime.utc(2023, 3, 10, 8, 15, 45)
            .millisecondsSinceEpoch
            .toDouble();
        expect(asDateHourMinute(input), equals(minute));
      });

      test('non-numeric returns null', () {
        expect(asDateHourMinute('abc'), isNull);
        expect(asDateHourMinute(null), isNull);
      });
    });

    group('toSetOfStrings', () {
      test('List converts to Set of strings', () {
        expect(toSetOfStrings(['a', 'b', 'c']), equals({'a', 'b', 'c'}));
      });

      test('List with duplicates deduplicates', () {
        expect(toSetOfStrings(['a', 'a', 'b']), equals({'a', 'b'}));
      });

      test('List with non-strings converts via toString', () {
        expect(toSetOfStrings([1, 2, 3]), equals({'1', '2', '3'}));
      });

      test('Set converts to Set of strings', () {
        expect(toSetOfStrings({'a', 'b', 'c'}), equals({'a', 'b', 'c'}));
      });

      test('Set with non-strings converts via toString', () {
        expect(toSetOfStrings({1, 2, 3}), equals({'1', '2', '3'}));
      });

      test('other Iterable (e.g. Iterable.generate) converts to Set', () {
        expect(toSetOfStrings(Iterable.generate(3, (i) => 'v$i')),
            equals({'v0', 'v1', 'v2'}));
      });

      test('non-Iterable returns null', () {
        expect(toSetOfStrings('abc'), isNull);
        expect(toSetOfStrings(123), isNull);
        expect(toSetOfStrings(null), isNull);
      });

      test('empty List or Set returns empty Set', () {
        expect(toSetOfStrings([]), equals(<String>{}));
        expect(toSetOfStrings(<String>{}), equals(<String>{}));
      });
    });
  });
}
