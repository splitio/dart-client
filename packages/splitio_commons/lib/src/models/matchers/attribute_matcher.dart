import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class AttributeMatcher extends Matcher {
  final Matcher delegate;
  final bool negate;
  final String? attribute;

  const AttributeMatcher({
    required this.delegate,
    this.negate = false,
    this.attribute,
  });

  @override
  bool match(Object? value, MatchingContext ctx) => false;
}
