import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class ContainsAnyOfMatcher extends Matcher {
  final List<String> values;
  const ContainsAnyOfMatcher({required this.values});

  @override
  bool match(Object? value, MatchingContext ctx) {
    return value is String && values.any((v) => value.contains(v));
  }
}
