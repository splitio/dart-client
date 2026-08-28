import 'flag_name.dart';
import 'result.dart';

ValidationResult<List<String>> validateFlagNames(
    List<String>? flags, String method) {
  if (flags == null || flags.isEmpty) {
    return ValidationResult.fail(
      '$method: feature flag names must be a non-empty array.',
    );
  }

  final warnings = <String>[];
  final seen = <String>{};
  final out = <String>[];

  for (final f in flags) {
    final r = validateFlagName(f, method);
    if (!r.isValid) {
      warnings.add(r.error!);
      continue;
    }
    if (r.warning != null) warnings.add(r.warning!);
    final v = r.value!;
    if (seen.add(v)) out.add(v);
  }

  if (out.isEmpty) {
    return ValidationResult.fail(
      '$method: feature flag names must be a non-empty array.',
    );
  }

  return ValidationResult.ok(
    out,
    warning: warnings.isEmpty ? null : warnings.join('\n'),
  );
}
