import 'package:splitio_commons/src/input_validation/flag_name.dart';
import 'package:test/test.dart';

void main() {
  group('validateFlagName', () {
    test('accepts a normal flag name', () {
      final r = validateFlagName('my_flag', 'getTreatment');
      expect(r.isValid, isTrue);
      expect(r.value, 'my_flag');
      expect(r.warning, isNull);
    });

    test('trims whitespace and warns', () {
      final r = validateFlagName('  my_flag  ', 'getTreatment');
      expect(r.isValid, isTrue);
      expect(r.value, 'my_flag');
      expect(r.warning, contains('whitespace'));
    });

    test('rejects empty string', () {
      final r = validateFlagName('', 'getTreatment');
      expect(r.isValid, isFalse);
    });

    test('rejects whitespace-only string', () {
      final r = validateFlagName('   ', 'getTreatment');
      expect(r.isValid, isFalse);
    });

    test('rejects null', () {
      final r = validateFlagName(null, 'getTreatment');
      expect(r.isValid, isFalse);
    });
  });
}
