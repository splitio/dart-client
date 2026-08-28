const int _baseEventSize = 1024;
const int _maxEventSize = 32 * 1024;
const int _maxProperties = 300;

const int _stringByte = 2;
const int _boolByte = 4;
const int _numberByte = 8;

class ValidatedProperties {
  final Map<String, Object?>? properties;
  final int size;

  const ValidatedProperties({required this.properties, required this.size});
}

/// Validates and normalises the properties map. Returns `null` properties on
/// hard failure (too many entries or over size limit).
///
/// - Values not of type String/num/bool/null are coerced to `null`.
/// - Returns the estimated event byte size, starting from a 1 KB base.
ValidatedProperties? validateProperties(Map<String, Object?>? maybeProperties) {
  if (maybeProperties == null) {
    return const ValidatedProperties(properties: null, size: _baseEventSize);
  }

  if (maybeProperties.length > _maxProperties) {
    return null;
  }

  final clone = <String, Object?>{...maybeProperties};
  var size = _baseEventSize;

  for (final entry in clone.entries) {
    size += entry.key.length * _stringByte;
    final val = entry.value;

    if (val == null) {
      // 0 bytes
    } else if (val is String) {
      size += val.length * _stringByte;
    } else if (val is num) {
      size += _numberByte;
    } else if (val is bool) {
      size += _boolByte;
    } else {
      clone[entry.key] = null;
    }

    if (size > _maxEventSize) return null;
  }

  return ValidatedProperties(properties: clone, size: size);
}
