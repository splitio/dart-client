import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('EqualToSetMatcher', () {
    const matcher = EqualToSetMatcher(compareTo: {'a', 'b', 'c'});

    test('matches exact set', () {
      expect(matcher.match(['a', 'b', 'c'], defaultCtx()), isTrue);
      expect(matcher.match(['c', 'a', 'b'], defaultCtx()),
          isTrue); // Order doesn't matter
    });

    test('does not match subset', () {
      expect(matcher.match(['a', 'b'], defaultCtx()), isFalse);
      expect(matcher.match(['a'], defaultCtx()), isFalse);
    });

    test('does not match superset', () {
      expect(matcher.match(['a', 'b', 'c', 'd'], defaultCtx()), isFalse);
    });

    test('does not match different set', () {
      expect(matcher.match(['x', 'y', 'z'], defaultCtx()), isFalse);
      expect(matcher.match(['a', 'b', 'x'], defaultCtx()), isFalse);
    });

    test('returns false for non-collection values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match('a,b,c', defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
    });

    test('handles empty set', () {
      const emptyMatcher = EqualToSetMatcher(compareTo: {});
      expect(emptyMatcher.match([], defaultCtx()), isTrue);
      expect(emptyMatcher.match(['a'], defaultCtx()), isFalse);
    });
  });

  group('ContainsAnyOfSetMatcher', () {
    const matcher = ContainsAnyOfSetMatcher(compareTo: {'a', 'b', 'c'});

    test('matches when contains one element', () {
      expect(matcher.match(['a'], defaultCtx()), isTrue);
      expect(matcher.match(['x', 'a', 'y'], defaultCtx()), isTrue);
    });

    test('matches when contains multiple elements', () {
      expect(matcher.match(['a', 'b'], defaultCtx()), isTrue);
      expect(matcher.match(['a', 'b', 'c'], defaultCtx()), isTrue);
    });

    test('does not match when contains none', () {
      expect(matcher.match(['x', 'y', 'z'], defaultCtx()), isFalse);
      expect(matcher.match([], defaultCtx()), isFalse);
    });

    test('returns false for non-collection values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match('a', defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
    });

    test('returns false for empty compareTo', () {
      const emptyMatcher = ContainsAnyOfSetMatcher(compareTo: {});
      expect(emptyMatcher.match(['a'], defaultCtx()), isFalse);
      expect(emptyMatcher.match([], defaultCtx()), isFalse);
    });
  });

  group('ContainsAllOfSetMatcher', () {
    const matcher = ContainsAllOfSetMatcher(compareTo: {'a', 'b'});

    test('matches when contains all elements', () {
      expect(matcher.match(['a', 'b'], defaultCtx()), isTrue);
      expect(matcher.match(['a', 'b', 'c'], defaultCtx()), isTrue);
      expect(matcher.match(['x', 'a', 'b', 'y'], defaultCtx()), isTrue);
    });

    test('does not match when missing some elements', () {
      expect(matcher.match(['a'], defaultCtx()), isFalse);
      expect(matcher.match(['b'], defaultCtx()), isFalse);
      expect(matcher.match(['a', 'c'], defaultCtx()), isFalse);
    });

    test('does not match when contains none', () {
      expect(matcher.match(['x', 'y'], defaultCtx()), isFalse);
      expect(matcher.match([], defaultCtx()), isFalse);
    });

    test('returns false for non-collection values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match('a,b', defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
    });

    test('returns false for empty compareTo', () {
      const emptyMatcher = ContainsAllOfSetMatcher(compareTo: {});
      expect(emptyMatcher.match(['a'], defaultCtx()), isFalse);
      expect(emptyMatcher.match([], defaultCtx()), isFalse);
    });
  });

  group('PartOfSetMatcher', () {
    const matcher = PartOfSetMatcher(compareTo: {'a', 'b', 'c'});

    test('matches when all elements are in compareTo', () {
      expect(matcher.match(['a'], defaultCtx()), isTrue);
      expect(matcher.match(['a', 'b'], defaultCtx()), isTrue);
      expect(matcher.match(['a', 'b', 'c'], defaultCtx()), isTrue);
    });

    test('does not match when any element not in compareTo', () {
      expect(matcher.match(['a', 'x'], defaultCtx()), isFalse);
      expect(matcher.match(['x', 'y'], defaultCtx()), isFalse);
      expect(matcher.match(['a', 'b', 'c', 'd'], defaultCtx()), isFalse);
    });

    test('does not match empty set', () {
      // PartOfSetMatcher returns false for empty sets
      expect(matcher.match([], defaultCtx()), isFalse);
    });

    test('returns false for non-collection values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match('a', defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
    });
  });
}
