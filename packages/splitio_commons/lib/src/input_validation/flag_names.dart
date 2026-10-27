import 'flag_name.dart';
import 'result.dart';

/// Validates a list of feature flag names (JS `validateDefinitions` parity).
///
/// Invalid entries (null/empty) are dropped and reported as ERROR-level
/// messages: through [onError] when given, otherwise folded into the result's
/// `warning` for backward compatibility. Whitespace-trimming notices are
/// always warnings.
ValidationResult<List<String>> validateFlagNames(
    List<String>? flags, String method,
    {void Function(String message)? onError}) {
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
      if (onError != null) {
        onError(r.error!);
      } else {
        warnings.add(r.error!);
      }
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
