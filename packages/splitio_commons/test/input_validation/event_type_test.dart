import 'package:splitio_commons/src/input_validation/event_type.dart';
import 'package:test/test.dart';

void main() {
  group('validateEventType', () {
    test('accepts alphanumeric + allowed punctuation', () {
      expect(validateEventType('purchase'), isTrue);
      expect(validateEventType('a1-b_c.d:e'), isTrue);
      expect(validateEventType('A'), isTrue);
    });

    test('rejects empty string', () {
      expect(validateEventType(''), isFalse);
    });

    test('rejects invalid first character', () {
      expect(validateEventType('_bad'), isFalse);
      expect(validateEventType('-bad'), isFalse);
      expect(validateEventType('.bad'), isFalse);
    });

    test('rejects over-length event type (>80)', () {
      expect(validateEventType('a' * 80), isTrue);
      expect(validateEventType('a' * 81), isFalse);
    });

    test('rejects disallowed characters', () {
      expect(validateEventType('bad event'), isFalse);
      expect(validateEventType('bad/event'), isFalse);
    });
  });
}
