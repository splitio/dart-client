import '../models/key.dart';
import 'result.dart';

const int _maxKeyLength = 1024;

ValidationResult<Key> validateKey(Key? key, String method) {
  if (key == null) {
    return ValidationResult.fail(
      '$method: you passed a null key. It must be a non-empty string.',
    );
  }
  if (key.matchingKey.isEmpty) {
    return ValidationResult.fail(
      '$method: you passed an empty key. It must be a non-empty string.',
    );
  }
  if (key.matchingKey.length > _maxKeyLength) {
    return ValidationResult.fail(
      '$method: key too long. It must have $_maxKeyLength characters or less.',
    );
  }
  final b = key.bucketingKey;
  if (b != null) {
    if (b.isEmpty) {
      return ValidationResult.fail(
        '$method: you passed an empty bucketingKey. It must be a non-empty string.',
      );
    }
    if (b.length > _maxKeyLength) {
      return ValidationResult.fail(
        '$method: bucketingKey too long. It must have $_maxKeyLength characters or less.',
      );
    }
  }
  return ValidationResult.ok(key);
}
