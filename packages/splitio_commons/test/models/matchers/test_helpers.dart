import 'package:splitio_commons/src/core/core.dart';
import 'package:splitio_commons/src/logger/logger.dart';

class StubEvaluationContext implements EvaluationContext {
  final Map<String, EvaluationResult> evaluations;
  final Set<String> segments;
  final Set<String> ruleBasedSegments;

  @override
  final SplitLogger? logger;

  StubEvaluationContext({
    this.logger,
    this.evaluations = const {},
    this.segments = const {},
    this.ruleBasedSegments = const {},
  });

  @override
  EvaluationResult evaluate(
    String matchingKey,
    String bucketingKey,
    String ruleName,
    Map<String, Object?> attributes,
  ) {
    return evaluations[ruleName] ??
        (treatment: 'control', label: 'default rule');
  }

  @override
  bool isInSegment(String segmentName, String key) {
    return segments.contains('$segmentName:$key') ||
        segments.contains(segmentName);
  }

  @override
  bool isInRuleBasedSegment(
    String segmentName,
    String key,
    String bucketingKey,
    Map<String, Object?> attributes,
  ) {
    return ruleBasedSegments.contains('$segmentName:$key') ||
        ruleBasedSegments.contains(segmentName);
  }
}

MatchingContext defaultCtx({
  String matchingKey = 'user1',
  String bucketingKey = 'user1',
  Map<String, Object?> attributes = const {},
  EvaluationContext? evaluator,
  SplitLogger? logger,
}) {
  return MatchingContext(
    matchingKey: matchingKey,
    bucketingKey: bucketingKey,
    attributes: attributes,
    evaluator: evaluator ?? StubEvaluationContext(),
    logger: logger,
  );
}
