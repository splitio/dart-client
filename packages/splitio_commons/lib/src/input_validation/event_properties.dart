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

/// Validates and normalises the properties map. Returns `null` only on hard
/// failure (estimated size over 32 KB).
///
/// - More than 300 properties is NOT a failure: the event is still tracked and
///   [onWarning] receives a warning (JS parity; the backend trims the excess).
/// - Values not of type String/num/bool/null are coerced to `null`, with a
///   warning per offending key sent to [onWarning].
/// - Returns the estimated event byte size, starting from a 1 KB base.
ValidatedProperties? validateProperties(
  Map<String, Object?>? maybeProperties, {
  String method = 'track',
  void Function(String message)? onWarning,
}) {
  if (maybeProperties == null) {
    return const ValidatedProperties(properties: null, size: _baseEventSize);
  }

  if (maybeProperties.length > _maxProperties) {
    onWarning?.call('$method: more than $_maxProperties properties were '
        'provided. Some of them will be trimmed when processed.');
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
      onWarning?.call('$method: Property "${entry.key}" is of invalid type. '
          'Setting value to null.');
    }

    if (size > _maxEventSize) return null;
  }

  return ValidatedProperties(properties: clone, size: size);
}

/// Validates `EvaluationOptions.properties` before they are attached to an
/// impression, with the same rules as `track` properties (spec §4.1, §16).
///
/// - Unsupported value types are set to `null` and reported to [onWarning].
/// - More than 300 entries is reported to [onWarning]; nothing is dropped.
/// - When the estimated size exceeds 32 KB the properties are dropped (the
///   evaluation and impression still proceed) and [onError] is called.
/// - An empty result is treated as absent (`null`).
Map<String, Object?>? validateEvaluationProperties(
  Map<String, Object?>? properties, {
  required String method,
  void Function(String message)? onWarning,
  void Function(String message)? onError,
}) {
  if (properties == null) return null;
  final validated =
      validateProperties(properties, method: method, onWarning: onWarning);
  if (validated == null) {
    onError?.call('$method: the maximum size allowed for the properties is '
        '$_maxEventSize bytes, which was exceeded. The impression will be '
        'recorded without properties.');
    return null;
  }
  final result = validated.properties;
  return result == null || result.isEmpty ? null : result;
}
