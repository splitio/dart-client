import 'package:splitio_commons/src/logger/logger.dart';

import 'evaluation_context.dart';

class MatchingContext {
  final String matchingKey;
  final String bucketingKey;
  final Map<String, Object?> attributes;
  final EvaluationContext evaluator;
  final SplitLogger? logger;

  const MatchingContext({
    required this.matchingKey,
    required this.bucketingKey,
    required this.attributes,
    required this.evaluator,
    this.logger,
  });
}
