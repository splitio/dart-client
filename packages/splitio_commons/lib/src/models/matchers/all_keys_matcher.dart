import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class AllKeysMatcher extends Matcher {
  const AllKeysMatcher();

  @override
  bool match(Object? value, MatchingContext ctx) => true;
}
