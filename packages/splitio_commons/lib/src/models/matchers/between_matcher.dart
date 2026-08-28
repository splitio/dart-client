import 'package:splitio_commons/src/core/core.dart';

import '../enums.dart';
import '../matcher.dart';

final class BetweenMatcher extends Matcher {
  final int start;
  final int end;
  final DataType dataType;
  const BetweenMatcher({
    required this.start,
    required this.end,
    required this.dataType,
  });

  @override
  bool match(Object? attributeValue, MatchingContext ctx) {
    if (dataType == DataType.datetime) {
      final v = asDateHourMinute(attributeValue);
      final s = asDateHourMinute(start);
      final e = asDateHourMinute(end);
      if (v == null || s == null || e == null) return false;
      return v >= s && v <= e;
    }
    final v = asLong(attributeValue);
    return v != null && v >= start && v <= end;
  }
}
