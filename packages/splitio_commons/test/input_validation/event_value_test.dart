import 'package:splitio_commons/src/input_validation/event_value.dart';
import 'package:test/test.dart';

void main() {
  group('validateEventValue', () {
    test('accepts null value', () {
      expect(validateEventValue(null), isTrue);
    });

    test('accepts finite values', () {
      expect(validateEventValue(0.0), isTrue);
      expect(validateEventValue(1.5), isTrue);
      expect(validateEventValue(-10.0), isTrue);
    });

    test('rejects NaN', () {
      expect(validateEventValue(double.nan), isFalse);
    });

    test('rejects positive infinity', () {
      expect(validateEventValue(double.infinity), isFalse);
    });

    test('rejects negative infinity', () {
      expect(validateEventValue(double.negativeInfinity), isFalse);
    });
  });
}
