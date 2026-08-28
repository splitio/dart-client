import 'result.dart';

ValidationResult<void> validateIfNotDestroyed({
  required bool isDestroyed,
  required String method,
}) {
  if (isDestroyed) {
    return ValidationResult<void>.fail(
      '$method: Client has already been destroyed - no calls possible.',
    );
  }
  return const ValidationResult<void>.ok(null);
}

ValidationResult<void> validateIfReady({
  required bool isReady,
  required String method,
}) {
  if (!isReady) {
    return ValidationResult<void>.fail(
      '$method: the SDK is not ready to evaluate. Results may be incorrect. '
      'Make sure to wait for SDK readiness before using this method.',
    );
  }
  return const ValidationResult<void>.ok(null);
}
