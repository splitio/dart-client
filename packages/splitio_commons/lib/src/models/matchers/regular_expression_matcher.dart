import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class RegularExpressionMatcher extends Matcher {
  final String pattern;
  const RegularExpressionMatcher({required this.pattern});

  @override
  bool match(Object? value, MatchingContext ctx) {
    return value is String && RegExp(pattern).hasMatch(value);
  }
}
