import 'package:splitio_commons/src/input_validation/event_properties.dart';
import 'package:test/test.dart';

void main() {
  evaluationPropertiesTests();
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

    test('warns and keeps the event when properties exceed 300', () {
      final many = {for (var i = 0; i < 301; i++) 'k$i': 'v'};
      final warnings = <String>[];
      final result = validateProperties(many, onWarning: warnings.add);
      expect(result, isNotNull);
      expect(result!.properties, hasLength(301));
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('more than 300 properties'));
    });

    test('warns naming the key when a value type is coerced to null', () {
      final warnings = <String>[];
      final result = validateProperties({
        'list': [1, 2]
      }, method: 'track', onWarning: warnings.add)!;
      expect(result.properties, {'list': null});
      expect(warnings.single, contains('track'));
      expect(warnings.single, contains('"list"'));
    });

    test('does not warn for valid properties', () {
      final warnings = <String>[];
      validateProperties({'a': 1}, onWarning: warnings.add);
      expect(warnings, isEmpty);
    });

    test('rejects when total byte size exceeds 32KB', () {
      final huge = {'a': 'x' * (32 * 1024)};
      expect(validateProperties(huge), isNull);
    });
  });
}

void evaluationPropertiesTests() {
  group('validateEvaluationProperties', () {
    test('returns null for null and for empty maps', () {
      expect(
          validateEvaluationProperties(null, method: 'getTreatment'), isNull);
      expect(validateEvaluationProperties({}, method: 'getTreatment'), isNull);
    });

    test('keeps valid values', () {
      expect(
          validateEvaluationProperties({'a': 'x', 'b': 1, 'c': true, 'd': null},
              method: 'getTreatment'),
          {'a': 'x', 'b': 1, 'c': true, 'd': null});
    });

    test('nulls non-JSON values and warns naming the property', () {
      final warnings = <String>[];
      final result = validateEvaluationProperties(
          {'when': DateTime(2020), 'ok': 'yes'},
          method: 'getTreatment', onWarning: warnings.add);
      expect(result, {'when': null, 'ok': 'yes'});
      expect(warnings.single, contains('getTreatment'));
      expect(warnings.single, contains('"when"'));
    });

    test('warns above 300 entries but keeps them', () {
      final warnings = <String>[];
      final result = validateEvaluationProperties(
          {for (var i = 0; i < 301; i++) 'k$i': i},
          method: 'getTreatment', onWarning: warnings.add);
      expect(result, hasLength(301));
      expect(warnings, hasLength(1));
    });

    test('drops properties and reports an error above 32 KB', () {
      final errors = <String>[];
      final result = validateEvaluationProperties({'big': 'x' * 20000},
          method: 'getTreatment', onError: errors.add);
      expect(result, isNull);
      expect(errors.single, contains('32768 bytes'));
    });
  });
}
