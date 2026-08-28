import 'result.dart';

final RegExp _flagSetRegex = RegExp(r'^[a-z0-9][_a-z0-9]{0,49}$');
final RegExp _hasUpper = RegExp(r'[A-Z]');
final RegExp _trimEdges = RegExp(r'^\s+|\s+$');

ValidationResult<String> validateFlagSet(String? name, String method) {
  if (name == null) {
    return ValidationResult.fail(
      '$method: flag set must be a non-empty string.',
    );
  }
  var trimmed = name.replaceAll(_trimEdges, '');
  if (trimmed.isEmpty) {
    return ValidationResult.fail(
      '$method: flag set must be a non-empty string.',
    );
  }
  String? warning;
  if (_hasUpper.hasMatch(trimmed)) {
    warning =
        '$method: flag set "$trimmed" should be all lowercase — converting to lowercase.';
    trimmed = trimmed.toLowerCase();
  }
  if (!_flagSetRegex.hasMatch(trimmed)) {
    return ValidationResult.fail(
      '$method: you passed "$name", flag set must adhere to '
      r'/^[a-z0-9][_a-z0-9]{0,49}$/. "$name" was discarded.',
    );
  }
  return warning == null
      ? ValidationResult.ok(trimmed)
      : ValidationResult.ok(trimmed, warning: warning);
}

ValidationResult<List<String>> validateFlagSets(
    List<String>? sets, String method) {
  if (sets == null || sets.isEmpty) {
    return ValidationResult.fail(
      '$method: flag sets must be a non-empty array.',
    );
  }
  final warnings = <String>[];
  final valid = <String>{};
  for (final s in sets) {
    final r = validateFlagSet(s, method);
    if (!r.isValid) {
      warnings.add(r.error!);
      continue;
    }
    if (r.warning != null) warnings.add(r.warning!);
    valid.add(r.value!);
  }
  if (valid.isEmpty) {
    return ValidationResult.fail(
      '$method: flag sets must be a non-empty array.',
    );
  }
  final sorted = valid.toList()..sort();
  return ValidationResult.ok(
    sorted,
    warning: warnings.isEmpty ? null : warnings.join('\n'),
  );
}
