import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class BooleanMatcher extends Matcher {
  final bool value;
  const BooleanMatcher({required this.value});

  @override
  bool match(Object? attributeValue, MatchingContext ctx) {
    final v = asBoolean(attributeValue);
    return v != null && v == value;
  }
}
