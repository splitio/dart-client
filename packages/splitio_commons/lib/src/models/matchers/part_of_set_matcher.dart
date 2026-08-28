import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class PartOfSetMatcher extends Matcher {
  final Set<String> compareTo;
  const PartOfSetMatcher({required this.compareTo});

  @override
  bool match(Object? value, MatchingContext ctx) {
    final set = toSetOfStrings(value);
    if (set == null || set.isEmpty) return false;
    return set.every((e) => compareTo.contains(e));
  }
}
