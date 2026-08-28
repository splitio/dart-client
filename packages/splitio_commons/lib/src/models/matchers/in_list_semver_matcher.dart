import 'package:splitio_commons/src/core/core.dart';

import '../matcher.dart';

final class InListSemverMatcher extends Matcher {
  final List<String> versions;
  const InListSemverMatcher({required this.versions});

  @override
  bool match(Object? value, MatchingContext ctx) {
    if (value is! String) return false;
    final v = Semver.build(value);
    if (v == null) return false;
    final normalized = v.version();
    for (final ver in versions) {
      final s = Semver.build(ver);
      if (s != null && s.version() == normalized) return true;
    }
    return false;
  }
}
