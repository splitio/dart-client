import 'package:splitio_commons/src/input_validation/event_properties.dart';
import 'package:test/test.dart';

void main() {
  group('validateProperties', () {
    test('returns null properties with base size when input is null', () {
      final result = validateProperties(null)!;
      expect(result.properties, isNull);
      expect(result.size, 1024);
    });

    test('accepts allowed value types', () {
      final result = validateProperties({
        'a': 'x',
        'b': 1,
        'c': true,
        'd': null,
      })!;
      expect(result.properties, {
        'a': 'x',
        'b': 1,
        'c': true,
        'd': null,
      });
      expect(result.size >= 1024, isTrue);
    });

    test('coerces disallowed value types to null', () {
      final result = validateProperties({
        'a': [1, 2, 3]
      })!;
      expect(result.properties, {'a': null});
    });

    test('rejects when properties exceed 300', () {
      final many = {for (var i = 0; i < 301; i++) 'k$i': 'v'};
      expect(validateProperties(many), isNull);
    });

    test('rejects when total byte size exceeds 32KB', () {
      final huge = {'a': 'x' * (32 * 1024)};
      expect(validateProperties(huge), isNull);
    });
  });
}
