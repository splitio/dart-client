import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class EndsWithAnyOfMatcher extends Matcher {
  final List<String> values;
  const EndsWithAnyOfMatcher({required this.values});

  @override
  bool match(Object? value, MatchingContext ctx) {
    return value is String && values.any((v) => value.endsWith(v));
  }
}
