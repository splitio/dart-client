import 'result.dart';

final RegExp _trimEdges = RegExp(r'^[\s\uFEFF\xA0]+|[\s\uFEFF\xA0]+$');

ValidationResult<String> validateFlagName(String? flag, String method) {
  if (flag == null) {
    return ValidationResult.fail(
      '$method: you passed a null feature flag name. It must be a non-empty string.',
    );
  }
  final trimmed = flag.replaceAll(_trimEdges, '');
  if (trimmed.isEmpty) {
    return ValidationResult.fail(
      '$method: you passed an empty feature flag name. It must be a non-empty string.',
    );
  }
  if (trimmed != flag) {
    return ValidationResult.ok(
      trimmed,
      warning:
          '$method: feature flag name "$flag" has extra whitespace, trimming.',
    );
  }
  return ValidationResult.ok(trimmed);
}
