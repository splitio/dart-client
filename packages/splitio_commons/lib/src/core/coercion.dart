int? asLong(Object? value) {
  if (value is int) return value;
  return null;
}

bool? asBoolean(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
  }
  return null;
}

int? asDate(Object? value) {
  final millis = asLong(value);
  if (millis == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  return DateTime.utc(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
}

int? asDateHourMinute(Object? value) {
  final millis = asLong(value);
  if (millis == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  return DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute)
      .millisecondsSinceEpoch;
}

Set<String>? toSetOfStrings(Object? value) {
  if (value is List) {
    return value.map((e) => e.toString()).toSet();
  }
  return null;
}
