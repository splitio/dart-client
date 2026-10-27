import '../models/key.dart';
import 'result.dart';

// Spec §16 / Node parity (javascript-commons `validateKeyValue`): keys are
// trimmed, must be non-empty after trimming, and limited to 250 chars.
const int _maxKeyLength = 250;

/// Validates [key] and, on success, returns a **trimmed** [Key] — the
/// trimmed `matchingKey`/`bucketingKey` MUST be what callers go on to use
/// for evaluation, bucketing, impressions and events (spec §16). Trimming
/// happens here, before the length/emptiness checks, so a key that is only
/// whitespace is treated as empty and a key that is over-length only
/// because of surrounding whitespace is accepted.
ValidationResult<Key> validateKey(Key? key, String method) {
  if (key == null) {
    return ValidationResult.fail(
      '$method: you passed a null key. It must be a non-empty string.',
    );
  }
  final matchingKey = key.matchingKey.trim();
  if (matchingKey.isEmpty) {
    return ValidationResult.fail(
      '$method: you passed an empty key. It must be a non-empty string.',
    );
  }
  if (matchingKey.length > _maxKeyLength) {
    return ValidationResult.fail(
      '$method: key too long. It must have $_maxKeyLength characters or less.',
    );
  }
  final rawBucketingKey = key.bucketingKey;
  String? bucketingKey;
  if (rawBucketingKey != null) {
    bucketingKey = rawBucketingKey.trim();
    if (bucketingKey.isEmpty) {
      return ValidationResult.fail(
        '$method: you passed an empty bucketingKey. It must be a non-empty string.',
      );
    }
    if (bucketingKey.length > _maxKeyLength) {
      return ValidationResult.fail(
        '$method: bucketingKey too long. It must have $_maxKeyLength characters or less.',
      );
    }
  }
  return ValidationResult.ok(
    Key(matchingKey: matchingKey, bucketingKey: bucketingKey),
  );
}
