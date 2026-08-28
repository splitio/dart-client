import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('UserDefinedSegmentMatcher', () {
    test('matches when user is in segment', () {
      final evaluator = StubEvaluationContext(
        segments: {'premium_users'},
      );
      const matcher = UserDefinedSegmentMatcher(segmentName: 'premium_users');

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isTrue);
    });

    test('does not match when user is not in segment', () {
      final evaluator = StubEvaluationContext(
        segments: {'premium_users'},
      );
      const matcher = UserDefinedSegmentMatcher(segmentName: 'beta_users');

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isFalse);
    });

    test('matches with key-specific segment', () {
      final evaluator = StubEvaluationContext(
        segments: {'premium_users:user123'},
      );
      const matcher = UserDefinedSegmentMatcher(segmentName: 'premium_users');

      final ctx = defaultCtx(matchingKey: 'user123', evaluator: evaluator);
      expect(matcher.match(null, ctx), isTrue);
    });

    test('does not match different key in key-specific segment', () {
      final evaluator = StubEvaluationContext(
        segments: {'premium_users:user123'},
      );
      const matcher = UserDefinedSegmentMatcher(segmentName: 'premium_users');

      final ctx = defaultCtx(matchingKey: 'user456', evaluator: evaluator);
      expect(matcher.match(null, ctx), isFalse);
    });

    test('uses matchingKey from context', () {
      final evaluator = StubEvaluationContext(
        segments: {'vip_users:alice'},
      );
      const matcher = UserDefinedSegmentMatcher(segmentName: 'vip_users');

      final ctx = defaultCtx(matchingKey: 'alice', evaluator: evaluator);
      expect(matcher.match(null, ctx), isTrue);

      final ctx2 = defaultCtx(matchingKey: 'bob', evaluator: evaluator);
      expect(matcher.match(null, ctx2), isFalse);
    });

    test('value parameter is ignored', () {
      final evaluator = StubEvaluationContext(segments: {'segment'});
      const matcher = UserDefinedSegmentMatcher(segmentName: 'segment');

      expect(
          matcher.match('anything', defaultCtx(evaluator: evaluator)), isTrue);
      expect(matcher.match(123, defaultCtx(evaluator: evaluator)), isTrue);
      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isTrue);
    });
  });

  group('RuleBasedSegmentMatcher', () {
    test('matches when user is in rule-based segment', () {
      final evaluator = StubEvaluationContext(
        ruleBasedSegments: {'dynamic_segment'},
      );
      const matcher = RuleBasedSegmentMatcher(segmentName: 'dynamic_segment');

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isTrue);
    });

    test('does not match when user is not in rule-based segment', () {
      final evaluator = StubEvaluationContext(
        ruleBasedSegments: {'segment_a'},
      );
      const matcher = RuleBasedSegmentMatcher(segmentName: 'segment_b');

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isFalse);
    });

    test('matches with key-specific rule-based segment', () {
      final evaluator = StubEvaluationContext(
        ruleBasedSegments: {'dynamic_segment:user123'},
      );
      const matcher = RuleBasedSegmentMatcher(segmentName: 'dynamic_segment');

      final ctx = defaultCtx(matchingKey: 'user123', evaluator: evaluator);
      expect(matcher.match(null, ctx), isTrue);
    });

    test('does not match different key in key-specific rule-based segment', () {
      final evaluator = StubEvaluationContext(
        ruleBasedSegments: {'dynamic_segment:user123'},
      );
      const matcher = RuleBasedSegmentMatcher(segmentName: 'dynamic_segment');

      final ctx = defaultCtx(matchingKey: 'user456', evaluator: evaluator);
      expect(matcher.match(null, ctx), isFalse);
    });

    test('passes full context to evaluator', () {
      final evaluator = StubEvaluationContext(
        ruleBasedSegments: {'contextual_segment'},
      );
      const matcher =
          RuleBasedSegmentMatcher(segmentName: 'contextual_segment');

      final ctx = defaultCtx(
        matchingKey: 'user123',
        bucketingKey: 'bucket456',
        attributes: {'country': 'US', 'age': 25},
        evaluator: evaluator,
      );

      expect(matcher.match(null, ctx), isTrue);
    });

    test('value parameter is ignored', () {
      final evaluator = StubEvaluationContext(ruleBasedSegments: {'segment'});
      const matcher = RuleBasedSegmentMatcher(segmentName: 'segment');

      expect(
          matcher.match('anything', defaultCtx(evaluator: evaluator)), isTrue);
      expect(matcher.match(123, defaultCtx(evaluator: evaluator)), isTrue);
      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isTrue);
    });

    test('differentiates from UserDefinedSegmentMatcher', () {
      // A key in a user-defined segment should not match a rule-based segment
      final evaluator = StubEvaluationContext(
        segments: {'segment_name'}, // Only in user-defined segments
        ruleBasedSegments: {}, // Not in rule-based segments
      );
      const matcher = RuleBasedSegmentMatcher(segmentName: 'segment_name');

      expect(matcher.match(null, defaultCtx(evaluator: evaluator)), isFalse);
    });
  });
}
