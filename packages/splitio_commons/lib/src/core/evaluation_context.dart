typedef EvaluationResult = ({String treatment, String label});

abstract class EvaluationContext {
  EvaluationResult evaluate(
    String matchingKey,
    String bucketingKey,
    String ruleName,
    Map<String, Object?> attributes,
  );

  bool isInSegment(String segmentName, String key);

  bool isInRuleBasedSegment(
    String segmentName,
    String key,
    String bucketingKey,
    Map<String, Object?> attributes,
  );
}
