import 'package:splitio_commons/src/core/core.dart';

import '../enums.dart';
import '../matcher.dart';

final class LessThanOrEqualToMatcher extends Matcher {
  final int value;
  final DataType dataType;
  const LessThanOrEqualToMatcher({required this.value, required this.dataType});

  @override
  bool match(Object? attributeValue, MatchingContext ctx) {
    if (dataType == DataType.datetime) {
      final v = asDateHourMinute(attributeValue);
      final c = asDateHourMinute(value);
      if (v == null || c == null) return false;
      return v <= c;
    }
    final v = asLong(attributeValue);
    return v != null && v <= value;
  }
}
