import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';
import 'semver_attribute.dart';

final class LessThanOrEqualToSemverMatcher extends Matcher {
  final String version;
  const LessThanOrEqualToSemverMatcher({required this.version});

  @override
  bool match(Object? value, MatchingContext ctx) {
    if (value is! String) return false;
    final v = parseAttributeSemver(value, ctx, 'LESS_THAN_OR_EQUAL_TO_SEMVER');
    final c = Semver.build(version);
    if (v == null || c == null) return false;
    return v.comparePrecedence(c) <= 0;
  }
}
