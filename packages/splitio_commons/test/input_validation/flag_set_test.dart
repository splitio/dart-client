import 'package:splitio_commons/src/input_validation/flag_set.dart';
import 'package:test/test.dart';

void main() {
  group('validateFlagSet', () {
    test('accepts valid lowercase name', () {
      final r = validateFlagSet('my_set1', 'getTreatmentsByFlagSets');
      expect(r.isValid, isTrue);
      expect(r.value, 'my_set1');
    });

    test('lowercases and warns', () {
      final r = validateFlagSet('MySet', 'getTreatmentsByFlagSets');
      expect(r.isValid, isTrue);
      expect(r.value, 'myset');
      expect(r.warning, isNotNull);
    });

    test('rejects invalid characters', () {
      final r = validateFlagSet('bad-set', 'getTreatmentsByFlagSets');
      expect(r.isValid, isFalse);
    });

    test('rejects starting with underscore', () {
      final r = validateFlagSet('_bad', 'getTreatmentsByFlagSets');
      expect(r.isValid, isFalse);
    });

    test('rejects > 50 chars', () {
      final r = validateFlagSet('a' * 51, 'getTreatmentsByFlagSets');
      expect(r.isValid, isFalse);
    });

    test('accepts exactly 50 chars', () {
      final r = validateFlagSet('a' * 50, 'getTreatmentsByFlagSets');
      expect(r.isValid, isTrue);
    });

    test('rejects empty', () {
      final r = validateFlagSet('', 'getTreatmentsByFlagSets');
      expect(r.isValid, isFalse);
    });
  });

  group('validateFlagSets', () {
    test('dedupes and sorts alphabetically', () {
      final r =
          validateFlagSets(['b', 'a', 'c', 'a'], 'getTreatmentsByFlagSets');
      expect(r.isValid, isTrue);
      expect(r.value, ['a', 'b', 'c']);
    });

    test('drops invalid, keeps valid', () {
      final r = validateFlagSets(
          ['ok', 'BAD-SET', 'also_ok'], 'getTreatmentsByFlagSets');
      expect(r.isValid, isTrue);
      expect(r.value, ['also_ok', 'ok']);
      expect(r.warning, isNotNull);
    });

    test('rejects null or empty', () {
      expect(validateFlagSets(null, 'x').isValid, isFalse);
      expect(validateFlagSets(<String>[], 'x').isValid, isFalse);
    });

    test('rejects when all invalid', () {
      expect(validateFlagSets(['BAD-SET'], 'x').isValid, isFalse);
    });
  });
}
