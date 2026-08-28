final class KeyImpression {
  final String feature;
  final String keyName;
  final String? bucketingKey;
  final String treatment;
  final String label;
  final int changeNumber;
  final int time;
  int? pt;
  final Map<String, Object?>? properties;

  KeyImpression({
    required this.feature,
    required this.keyName,
    this.bucketingKey,
    required this.treatment,
    required this.label,
    required this.changeNumber,
    required this.time,
    this.pt,
    this.properties,
  });
}
