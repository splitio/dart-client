import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('BooleanMatcher', () {
    group('value = true', () {
      const matcher = BooleanMatcher(value: true);

      test('matches true boolean', () {
        expect(matcher.match(true, defaultCtx()), isTrue);
      });

      test('matches truthy string representations', () {
        expect(matcher.match('true', defaultCtx()), isTrue);
        expect(matcher.match('TRUE', defaultCtx()), isTrue);
        expect(matcher.match('True', defaultCtx()), isTrue);
      });

      test('does not match false boolean', () {
        expect(matcher.match(false, defaultCtx()), isFalse);
      });

      test('does not match falsy string representations', () {
        expect(matcher.match('false', defaultCtx()), isFalse);
        expect(matcher.match('FALSE', defaultCtx()), isFalse);
      });

      test('returns false for non-boolean values', () {
        expect(matcher.match(null, defaultCtx()), isFalse);
        expect(matcher.match(1, defaultCtx()), isFalse);
        expect(matcher.match(0, defaultCtx()), isFalse);
        expect(matcher.match('yes', defaultCtx()), isFalse);
        expect(matcher.match('', defaultCtx()), isFalse);
      });
    });

    group('value = false', () {
      const matcher = BooleanMatcher(value: false);

      test('matches false boolean', () {
        expect(matcher.match(false, defaultCtx()), isTrue);
      });

      test('matches falsy string representations', () {
        expect(matcher.match('false', defaultCtx()), isTrue);
        expect(matcher.match('FALSE', defaultCtx()), isTrue);
        expect(matcher.match('False', defaultCtx()), isTrue);
      });

      test('does not match true boolean', () {
        expect(matcher.match(true, defaultCtx()), isFalse);
      });

      test('does not match truthy string representations', () {
        expect(matcher.match('true', defaultCtx()), isFalse);
        expect(matcher.match('TRUE', defaultCtx()), isFalse);
      });

      test('returns false for non-boolean values', () {
        expect(matcher.match(null, defaultCtx()), isFalse);
        expect(matcher.match(1, defaultCtx()), isFalse);
        expect(matcher.match(0, defaultCtx()), isFalse);
        expect(matcher.match('no', defaultCtx()), isFalse);
      });
    });
  });
}
