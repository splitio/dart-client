import 'package:splitio_commons/src/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Coercion', () {
    group('asLong', () {
      test('int value passes through', () {
        expect(asLong(42), equals(42));
        expect(asLong(0), equals(0));
        expect(asLong(-1), equals(-1));
      });

      test('non-int returns null', () {
        expect(asLong('42'), isNull);
        expect(asLong(3.14), isNull);
        expect(asLong(null), isNull);
        expect(asLong(true), isNull);
        expect(asLong([1]), isNull);
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

      test('non-int returns null', () {
        expect(asDate('12345'), isNull);
        expect(asDate(null), isNull);
        expect(asDate(3.14), isNull);
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

      test('non-int returns null', () {
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

      test('non-List returns null', () {
        expect(toSetOfStrings('abc'), isNull);
        expect(toSetOfStrings(123), isNull);
        expect(toSetOfStrings(null), isNull);
        expect(toSetOfStrings({'a', 'b'}), isNull);
      });

      test('empty List returns empty Set', () {
        expect(toSetOfStrings([]), equals(<String>{}));
      });
    });
  });
}
