import 'package:splitio_commons/src/core/core.dart';

import '../enums.dart';
import '../matcher.dart';

final class EqualToMatcher extends Matcher {
  final int value;
  final DataType dataType;
  const EqualToMatcher({required this.value, required this.dataType});

  @override
  bool match(Object? attributeValue, MatchingContext ctx) {
    if (dataType == DataType.datetime) {
      final v = asDate(attributeValue);
      final c = asDate(value);
      if (v == null || c == null) return false;
      return v == c;
    }
    final v = asLong(attributeValue);
    return v != null && v == value;
  }
}
