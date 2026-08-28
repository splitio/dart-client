import 'package:splitio_commons/src/input_validation/traffic_type.dart';
import 'package:test/test.dart';

void main() {
  group('validateTrafficType', () {
    test('returns lowercase value unchanged when already lowercase', () {
      final r = validateTrafficType('user')!;
      expect(r.value, 'user');
      expect(r.wasLowercased, isFalse);
    });

    test('lowercases and flags when uppercase letters present', () {
      final r = validateTrafficType('User')!;
      expect(r.value, 'user');
      expect(r.wasLowercased, isTrue);
    });

    test('returns null on empty string', () {
      expect(validateTrafficType(''), isNull);
    });
  });
}
