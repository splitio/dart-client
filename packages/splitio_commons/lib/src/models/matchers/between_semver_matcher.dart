import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class BetweenSemverMatcher extends Matcher {
  final String start;
  final String end;
  const BetweenSemverMatcher({required this.start, required this.end});

  @override
  bool match(Object? value, MatchingContext ctx) {
    if (value is! String) return false;
    final v = Semver.build(value);
    final s = Semver.build(start);
    final e = Semver.build(end);
    if (v == null || s == null || e == null) return false;
    return v.comparePrecedence(s) >= 0 && v.comparePrecedence(e) <= 0;
  }
}
