import 'package:splitio_commons/src/core/core.dart';
import 'package:splitio_commons/src/models/models.dart';

/// Evaluates a condition's matcher group. Mirrors the .NET SDK's
/// `CombiningMatcher.Match`: an empty group never matches, and the AND combiner
/// requires every delegate to match.
bool matchCombining(
  CombiningMatcher combining,
  String matchingKey,
  String? bucketingKey,
  Attributes attributes,
  EvaluationContext ctx,
) {
  if (combining.delegates.isEmpty) return false;
  switch (combining.combiner) {
    case CombinerEnum.and:
      return combining.delegates.every(
        (m) => _matchCombined(m, matchingKey, bucketingKey, attributes, ctx),
      );
  }
}

bool _matchCombined(
  AttributeMatcher combined,
  String matchingKey,
  String? bucketingKey,
  Attributes attributes,
  EvaluationContext ctx,
) {
  final Object? value;
  if (combined.attribute != null) {
    value = attributes[combined.attribute];
    // A null/missing attribute always yields false — negate applies only to
    // the delegate's result, not to this short-circuit (spec §5.4).
    if (value == null) return false;
  } else {
    value = matchingKey;
  }

  final matchingCtx = MatchingContext(
    matchingKey: matchingKey,
    bucketingKey: bucketingKey ?? matchingKey,
    attributes: attributes,
    evaluator: ctx,
  );

  final result = combined.delegate.match(value, matchingCtx);
  return combined.negate ? !result : result;
}
