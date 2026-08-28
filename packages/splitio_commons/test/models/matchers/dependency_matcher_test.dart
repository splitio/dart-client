import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('DependencyMatcher', () {
    test('matches when dependent split returns matching treatment', () {
      final evaluator = StubEvaluationContext(
        evaluations: {
          'dependent_split': (treatment: 'on', label: 'matched'),
        },
      );
      const matcher = DependencyMatcher(
        split: 'dependent_split',
        treatments: ['on', 'enabled'],
      );

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isTrue);
    });

    test('does not match when dependent split returns non-matching treatment',
        () {
      final evaluator = StubEvaluationContext(
        evaluations: {
          'dependent_split': (treatment: 'off', label: 'not matched'),
        },
      );
      const matcher = DependencyMatcher(
        split: 'dependent_split',
        treatments: ['on', 'enabled'],
      );

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isFalse);
    });

    test('uses default treatment when split not found', () {
      final evaluator = StubEvaluationContext(); // No evaluations configured
      const matcher = DependencyMatcher(
        split: 'unknown_split',
        treatments: ['on'],
      );

      // StubEvaluationContext returns 'control' as default treatment
      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isFalse);
    });

    test('matches control treatment if included in treatments list', () {
      final evaluator = StubEvaluationContext(); // Returns default 'control'
      const matcher = DependencyMatcher(
        split: 'any_split',
        treatments: ['control', 'on'],
      );

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isTrue);
    });

    test('passes matching context to evaluator', () {
      final evaluator = StubEvaluationContext(
        evaluations: {
          'feature_split': (treatment: 'premium', label: 'matched'),
        },
      );
      const matcher = DependencyMatcher(
        split: 'feature_split',
        treatments: ['premium'],
      );

      final ctx = defaultCtx(
        matchingKey: 'user123',
        bucketingKey: 'bucket456',
        attributes: {'plan': 'enterprise'},
        evaluator: evaluator,
      );

      expect(matcher.match(null, ctx), isTrue);
    });

    test('handles empty treatments list', () {
      final evaluator = StubEvaluationContext(
        evaluations: {
          'split': (treatment: 'on', label: 'matched'),
        },
      );
      const matcher = DependencyMatcher(split: 'split', treatments: []);

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isFalse);
    });

    test('value parameter is ignored', () {
      final evaluator = StubEvaluationContext(
        evaluations: {
          'split': (treatment: 'on', label: 'matched'),
        },
      );
      const matcher = DependencyMatcher(split: 'split', treatments: ['on']);

      // Value should not affect the result
      expect(
          matcher.match('anything', defaultCtx(evaluator: evaluator)), isTrue);
      expect(matcher.match(123, defaultCtx(evaluator: evaluator)), isTrue);
      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isTrue);
    });
  });
}
