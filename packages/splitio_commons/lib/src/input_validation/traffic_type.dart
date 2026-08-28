final RegExp _capitalLettersRegex = RegExp(r'[A-Z]');

class ValidatedTrafficType {
  final String value;
  final bool wasLowercased;

  const ValidatedTrafficType(
      {required this.value, required this.wasLowercased});
}

ValidatedTrafficType? validateTrafficType(String trafficType) {
  if (trafficType.isEmpty) return null;
  final hasUpper = _capitalLettersRegex.hasMatch(trafficType);
  return ValidatedTrafficType(
    value: hasUpper ? trafficType.toLowerCase() : trafficType,
    wasLowercased: hasUpper,
  );
}
