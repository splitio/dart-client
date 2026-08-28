import 'package:splitio_commons/src/core/core.dart';

class StubEvaluationContext implements EvaluationContext {
  final Map<String, EvaluationResult> evaluations;
  final Set<String> segments;
  final Set<String> ruleBasedSegments;

  StubEvaluationContext({
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
}) {
  return MatchingContext(
    matchingKey: matchingKey,
    bucketingKey: bucketingKey,
    attributes: attributes,
    evaluator: evaluator ?? StubEvaluationContext(),
  );
}
