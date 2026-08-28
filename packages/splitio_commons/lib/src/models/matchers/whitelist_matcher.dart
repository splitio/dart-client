import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class WhitelistMatcher extends Matcher {
  final Set<String> whitelist;
  const WhitelistMatcher({required this.whitelist});

  @override
  bool match(Object? value, MatchingContext ctx) {
    return value is String && whitelist.contains(value);
  }
}
