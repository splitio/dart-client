import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class ContainsAllOfSetMatcher extends Matcher {
  final Set<String> compareTo;
  const ContainsAllOfSetMatcher({required this.compareTo});

  @override
  bool match(Object? value, MatchingContext ctx) {
    final set = toSetOfStrings(value);
    if (set == null || compareTo.isEmpty) return false;
    return compareTo.every((e) => set.contains(e));
  }
}
