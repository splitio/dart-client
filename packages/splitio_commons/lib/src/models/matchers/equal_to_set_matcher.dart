import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class EqualToSetMatcher extends Matcher {
  final Set<String> compareTo;
  const EqualToSetMatcher({required this.compareTo});

  @override
  bool match(Object? value, MatchingContext ctx) {
    final set = toSetOfStrings(value);
    if (set == null) return false;
    return set.length == compareTo.length && set.containsAll(compareTo);
  }
}
