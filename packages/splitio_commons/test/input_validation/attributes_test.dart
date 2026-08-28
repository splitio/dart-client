import 'package:splitio_commons/src/input_validation/attributes.dart';
import 'package:test/test.dart';

void main() {
  group('validateAttributes', () {
    test('accepts null', () {
      final r = validateAttributes(null, 'getTreatment');
      expect(r.isValid, isTrue);
      expect(r.value, isNull);
    });

    test('accepts empty map', () {
      final r = validateAttributes({}, 'getTreatment');
      expect(r.isValid, isTrue);
      expect(r.value, isEmpty);
    });

    test('passes values through unchanged (engine coerces)', () {
      final r = validateAttributes({
        'a': 'x',
        'b': 1,
        'c': true,
        'd': null,
        'unsupported': Object(),
      }, 'getTreatment');
      expect(r.isValid, isTrue);
      expect(r.value?.length, 5);
      expect(r.value?['unsupported'], isA<Object>());
    });

    test('drops empty-key entries and warns', () {
      final r = validateAttributes({'': 'x', 'ok': 'y'}, 'getTreatment');
      expect(r.isValid, isTrue);
      expect(r.value?.containsKey(''), isFalse);
      expect(r.value?.containsKey('ok'), isTrue);
      expect(r.warning, isNotNull);
    });
  });
}
