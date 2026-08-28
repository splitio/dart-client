import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class ContainsAnyOfSetMatcher extends Matcher {
  final Set<String> compareTo;
  const ContainsAnyOfSetMatcher({required this.compareTo});

  @override
  bool match(Object? value, MatchingContext ctx) {
    final set = toSetOfStrings(value);
    if (set == null) return false;
    return set.any((e) => compareTo.contains(e));
  }
}
