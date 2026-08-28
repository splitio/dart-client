import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class GreaterThanOrEqualToSemverMatcher extends Matcher {
  final String version;
  const GreaterThanOrEqualToSemverMatcher({required this.version});

  @override
  bool match(Object? value, MatchingContext ctx) {
    if (value is! String) return false;
    final v = Semver.build(value);
    final c = Semver.build(version);
    if (v == null || c == null) return false;
    return v.comparePrecedence(c) >= 0;
  }
}
