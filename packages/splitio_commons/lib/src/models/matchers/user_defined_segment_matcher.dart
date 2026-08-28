import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class UserDefinedSegmentMatcher extends Matcher {
  final String segmentName;
  const UserDefinedSegmentMatcher({required this.segmentName});

  @override
  bool match(Object? value, MatchingContext ctx) {
    return ctx.evaluator.isInSegment(segmentName, ctx.matchingKey);
  }
}
