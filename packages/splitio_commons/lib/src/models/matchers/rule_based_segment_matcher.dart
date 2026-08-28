import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class RuleBasedSegmentMatcher extends Matcher {
  final String segmentName;
  const RuleBasedSegmentMatcher({required this.segmentName});

  @override
  bool match(Object? value, MatchingContext ctx) {
    return ctx.evaluator.isInRuleBasedSegment(
      segmentName,
      ctx.matchingKey,
      ctx.bucketingKey,
      ctx.attributes,
    );
  }
}
