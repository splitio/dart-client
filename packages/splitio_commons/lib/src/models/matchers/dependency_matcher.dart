import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class DependencyMatcher extends Matcher {
  final String split;
  final List<String> treatments;
  const DependencyMatcher({required this.split, required this.treatments});

  @override
  bool match(Object? value, MatchingContext ctx) {
    final result = ctx.evaluator.evaluate(
      ctx.matchingKey,
      ctx.bucketingKey,
      split,
      ctx.attributes,
    );
    return treatments.contains(result.treatment);
  }
}
