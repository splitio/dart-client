import 'package:splitio_commons/src/input_validation/flag_names.dart';
import 'package:test/test.dart';

void main() {
  group('validateFlagNames', () {
    test('accepts non-empty list of valid names', () {
      final r = validateFlagNames(['a', 'b', 'c'], 'getTreatments');
      expect(r.isValid, isTrue);
      expect(r.value, ['a', 'b', 'c']);
    });

    test('dedupes preserving first-seen order', () {
      final r = validateFlagNames(['a', 'b', 'a', 'c'], 'getTreatments');
      expect(r.isValid, isTrue);
      expect(r.value, ['a', 'b', 'c']);
    });

    test('drops invalid entries and warns', () {
      final r = validateFlagNames(['a', '', '  ', 'b'], 'getTreatments');
      expect(r.isValid, isTrue);
      expect(r.value, ['a', 'b']);
      expect(r.warning, isNotNull);
    });

    test('reports invalid entries through onError, not the warning', () {
      final errors = <String>[];
      final r = validateFlagNames(['a', '', ' b '], 'getTreatments',
          onError: errors.add);
      expect(r.value, ['a', 'b']);
      expect(errors, hasLength(1));
      expect(errors.single, contains('empty feature flag name'));
      expect(r.warning, contains('extra whitespace'));
      expect(r.warning, isNot(contains('empty feature flag name')));
    });

    test('trims individual entries', () {
      final r = validateFlagNames(['  a  ', 'b'], 'getTreatments');
      expect(r.isValid, isTrue);
      expect(r.value, ['a', 'b']);
    });

    test('rejects null list', () {
      final r = validateFlagNames(null, 'getTreatments');
      expect(r.isValid, isFalse);
    });

    test('rejects empty list', () {
      final r = validateFlagNames(<String>[], 'getTreatments');
      expect(r.isValid, isFalse);
    });

    test('rejects when all entries invalid', () {
      final r = validateFlagNames(['', '   '], 'getTreatments');
      expect(r.isValid, isFalse);
    });
  });
}
