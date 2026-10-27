import 'package:splitio_commons/src/input_validation/key.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:test/test.dart';

void main() {
  group('validateKey', () {
    test('accepts a normal matching key', () {
      final r = validateKey(const Key(matchingKey: 'user_a'), 'getTreatment');
      expect(r.isValid, isTrue);
      expect(r.value?.matchingKey, 'user_a');
    });

    test('accepts key with valid bucketingKey', () {
      final r = validateKey(
        const Key(matchingKey: 'user_a', bucketingKey: 'bucket_1'),
        'getTreatment',
      );
      expect(r.isValid, isTrue);
    });

    test('rejects null key', () {
      final r = validateKey(null, 'getTreatment');
      expect(r.isValid, isFalse);
      expect(r.error, contains('getTreatment'));
    });

    test('rejects empty matchingKey', () {
      final r = validateKey(const Key(matchingKey: ''), 'getTreatment');
      expect(r.isValid, isFalse);
    });

    test('rejects empty bucketingKey when provided', () {
      final r = validateKey(
        const Key(matchingKey: 'user_a', bucketingKey: ''),
        'getTreatment',
      );
      expect(r.isValid, isFalse);
    });

    test('rejects matchingKey > 250 chars', () {
      final r = validateKey(Key(matchingKey: 'a' * 251), 'getTreatment');
      expect(r.isValid, isFalse);
    });

    test('accepts matchingKey exactly 250 chars', () {
      final r = validateKey(Key(matchingKey: 'a' * 250), 'getTreatment');
      expect(r.isValid, isTrue);
    });

    test('rejects bucketingKey > 250 chars', () {
      final r = validateKey(
        Key(matchingKey: 'user_a', bucketingKey: 'b' * 251),
        'getTreatment',
      );
      expect(r.isValid, isFalse);
    });

    test('trims surrounding whitespace from matchingKey and bucketingKey', () {
      final r = validateKey(
        const Key(matchingKey: ' user_a ', bucketingKey: ' bucket_1 '),
        'getTreatment',
      );
      expect(r.isValid, isTrue);
      expect(r.value?.matchingKey, 'user_a');
      expect(r.value?.bucketingKey, 'bucket_1');
    });

    test('rejects a whitespace-only matchingKey', () {
      final r = validateKey(const Key(matchingKey: '   '), 'getTreatment');
      expect(r.isValid, isFalse);
    });

    test('rejects a whitespace-only bucketingKey', () {
      final r = validateKey(
        const Key(matchingKey: 'user_a', bucketingKey: '   '),
        'getTreatment',
      );
      expect(r.isValid, isFalse);
    });

    test(
        'accepts a matchingKey that is only over-length because of '
        'surrounding whitespace', () {
      final r = validateKey(
        Key(matchingKey: ' ${'a' * 250} '),
        'getTreatment',
      );
      expect(r.isValid, isTrue);
      expect(r.value?.matchingKey, 'a' * 250);
    });
  });
}
