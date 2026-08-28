final class Key {
  final String matchingKey;
  final String? bucketingKey;

  const Key({required this.matchingKey, this.bucketingKey});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Key &&
          matchingKey == other.matchingKey &&
          bucketingKey == other.bucketingKey;

  @override
  int get hashCode => Object.hash(matchingKey, bucketingKey);

  @override
  String toString() =>
      'Key(matchingKey: $matchingKey, bucketingKey: $bucketingKey)';
}
