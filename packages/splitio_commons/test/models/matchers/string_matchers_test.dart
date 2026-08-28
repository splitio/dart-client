import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('StartsWithAnyOfMatcher', () {
    const matcher = StartsWithAnyOfMatcher(values: ['hello', 'world']);

    test('matches string starting with any prefix', () {
      expect(matcher.match('hello there', defaultCtx()), isTrue);
      expect(matcher.match('world peace', defaultCtx()), isTrue);
      expect(matcher.match('hello', defaultCtx()), isTrue);
    });

    test('does not match string without matching prefix', () {
      expect(matcher.match('goodbye', defaultCtx()), isFalse);
      expect(matcher.match('the world', defaultCtx()), isFalse);
      expect(matcher.match('', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
      expect(matcher.match(true, defaultCtx()), isFalse);
      expect(matcher.match(<String>[], defaultCtx()), isFalse);
    });

    test('handles empty values list', () {
      const emptyMatcher = StartsWithAnyOfMatcher(values: []);
      expect(emptyMatcher.match('hello', defaultCtx()), isFalse);
    });

    test('is case-sensitive', () {
      expect(matcher.match('Hello there', defaultCtx()), isFalse);
      expect(matcher.match('HELLO', defaultCtx()), isFalse);
    });
  });

  group('EndsWithAnyOfMatcher', () {
    const matcher = EndsWithAnyOfMatcher(values: ['ing', 'ed']);

    test('matches string ending with any suffix', () {
      expect(matcher.match('running', defaultCtx()), isTrue);
      expect(matcher.match('walked', defaultCtx()), isTrue);
      expect(matcher.match('ing', defaultCtx()), isTrue);
    });

    test('does not match string without matching suffix', () {
      expect(matcher.match('run', defaultCtx()), isFalse);
      expect(matcher.match('walk', defaultCtx()), isFalse);
      expect(matcher.match('', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
      expect(matcher.match(true, defaultCtx()), isFalse);
    });

    test('handles empty values list', () {
      const emptyMatcher = EndsWithAnyOfMatcher(values: []);
      expect(emptyMatcher.match('running', defaultCtx()), isFalse);
    });

    test('is case-sensitive', () {
      expect(matcher.match('runniNG', defaultCtx()), isFalse);
      expect(matcher.match('walkED', defaultCtx()), isFalse);
    });
  });

  group('ContainsAnyOfMatcher', () {
    const matcher = ContainsAnyOfMatcher(values: ['foo', 'bar']);

    test('matches string containing any substring', () {
      expect(matcher.match('foo is here', defaultCtx()), isTrue);
      expect(matcher.match('the bar is open', defaultCtx()), isTrue);
      expect(matcher.match('foo', defaultCtx()), isTrue);
      expect(matcher.match('foobar', defaultCtx()), isTrue);
    });

    test('does not match string without any substring', () {
      expect(matcher.match('hello world', defaultCtx()), isFalse);
      expect(matcher.match('', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
      expect(matcher.match(true, defaultCtx()), isFalse);
    });

    test('handles empty values list', () {
      const emptyMatcher = ContainsAnyOfMatcher(values: []);
      expect(emptyMatcher.match('foobar', defaultCtx()), isFalse);
    });

    test('is case-sensitive', () {
      expect(matcher.match('FOO is here', defaultCtx()), isFalse);
      expect(matcher.match('the BAR is open', defaultCtx()), isFalse);
    });
  });

  group('RegularExpressionMatcher', () {
    const matcher = RegularExpressionMatcher(pattern: r'^\d{3}-\d{4}$');

    test('matches string matching pattern', () {
      expect(matcher.match('123-4567', defaultCtx()), isTrue);
      expect(matcher.match('000-0000', defaultCtx()), isTrue);
    });

    test('does not match string not matching pattern', () {
      expect(matcher.match('1234567', defaultCtx()), isFalse);
      expect(matcher.match('12-34567', defaultCtx()), isFalse);
      expect(matcher.match('abc-defg', defaultCtx()), isFalse);
      expect(matcher.match('', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
      expect(matcher.match(true, defaultCtx()), isFalse);
    });

    test('handles complex patterns', () {
      const emailMatcher = RegularExpressionMatcher(
        pattern: r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
      );
      expect(emailMatcher.match('test@example.com', defaultCtx()), isTrue);
      expect(emailMatcher.match('invalid-email', defaultCtx()), isFalse);
    });

    test('handles empty pattern', () {
      const emptyMatcher = RegularExpressionMatcher(pattern: '');
      expect(emptyMatcher.match('', defaultCtx()), isTrue);
      expect(emptyMatcher.match('any', defaultCtx()), isTrue);
    });
  });
}
