import 'package:splitio_commons/src/core/core.dart';

/// Parses a runtime attribute [value] as semver for [matcherName]. When it is
/// not a valid semver, logs an ERROR (Node/JS parity) and returns `null` so
/// the caller yields "no match".
Semver? parseAttributeSemver(
    String value, MatchingContext ctx, String matcherName) {
  final parsed = Semver.build(value);
  if (parsed == null) {
    ctx.logger?.error('$matcherName matcher: attribute value "$value" is not '
        'a valid semver; the condition does not match.');
  }
  return parsed;
}
