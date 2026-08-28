import 'package:splitio_commons/src/core/core.dart';

abstract class Matcher {
  const Matcher();
  bool match(Object? value, MatchingContext ctx);
}
