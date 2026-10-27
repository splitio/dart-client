import 'result.dart';

/// Validates the SDK key passed to `SplitFactory.create`. Per spec §16, the
/// SDK key MUST be trimmed and non-empty — a whitespace-only key is just as
/// invalid as an empty one and MUST also produce a `NoOp` factory.
ValidationResult<String> validateSdkKey(String sdkKey, String method) {
  if (sdkKey.trim().isEmpty) {
    return ValidationResult.fail(
      '$method: you passed an empty SDK key. It must be a non-empty string.',
    );
  }
  return ValidationResult.ok(sdkKey);
}
