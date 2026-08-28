import 'result.dart';

ValidationResult<Map<String, Object?>?> validateAttributes(
    Map<String, Object?>? attrs, String method) {
  if (attrs == null) return const ValidationResult.ok(null);

  final warnings = <String>[];
  final out = <String, Object?>{};

  for (final entry in attrs.entries) {
    if (entry.key.isEmpty) {
      warnings.add(
          '$method: attribute name must be a non-empty string. Ignored entry with empty key.');
      continue;
    }
    // Values pass through unchanged — engine coercion (spec §5) handles
    // unsupported types by returning the matcher's "missing attribute" outcome.
    out[entry.key] = entry.value;
  }

  return ValidationResult.ok(
    out,
    warning: warnings.isEmpty ? null : warnings.join('\n'),
  );
}
