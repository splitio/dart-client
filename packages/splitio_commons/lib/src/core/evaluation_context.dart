import 'package:splitio_commons/src/logger/logger.dart';

typedef EvaluationResult = ({String treatment, String label});

abstract class EvaluationContext {
  /// Logger made available to matchers (e.g. to report unparsable attribute
  /// values); `null` means matchers log nothing.
  SplitLogger? get logger;

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
