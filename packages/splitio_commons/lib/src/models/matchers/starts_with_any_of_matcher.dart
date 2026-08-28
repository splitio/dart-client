import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class StartsWithAnyOfMatcher extends Matcher {
  final List<String> values;
  const StartsWithAnyOfMatcher({required this.values});

  @override
  bool match(Object? value, MatchingContext ctx) {
    return value is String && values.any((v) => value.startsWith(v));
  }
}
