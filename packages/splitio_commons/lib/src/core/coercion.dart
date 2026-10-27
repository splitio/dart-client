/// Coerces [value] to a number for comparison. Accepts any finite `int` or
/// `double` and returns it unchanged (no truncation) — numeric matchers
/// MUST compare as numbers without truncation (`18.5 >= 18` is `true`,
/// `18.5 == 18` is `false`). `String`, `NaN`, `±Infinity`, and every other
/// type yield `null` (spec §5.5).
num? asNumber(Object? value) {
  if (value is num && value.isFinite) return value;
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
  final number = asNumber(value);
  if (number == null) return null;
  final millis = number.truncate();
  final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  return DateTime.utc(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
}

int? asDateHourMinute(Object? value) {
  final number = asNumber(value);
  if (number == null) return null;
  final millis = number.truncate();
  final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  return DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute)
      .millisecondsSinceEpoch;
}

/// Coerces [value] to a `Set<String>` for collection (`*_SET`) matchers.
/// Accepts any `Iterable` runtime value — a `List`, a `Set`, or any other
/// ordered/unordered collection — mapping each element via `toString()`.
/// Everything else (including `String`, which is not an `Iterable` in
/// Dart) yields `null` (spec §5.5).
Set<String>? toSetOfStrings(Object? value) {
  if (value is Iterable) {
    return value.map((e) => e.toString()).toSet();
  }
  return null;
}
