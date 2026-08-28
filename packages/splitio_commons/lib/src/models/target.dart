import 'attributes.dart';
import 'key.dart';

final class Target {
  final Key key;
  final Attributes attributes;
  final String? trafficType;

  const Target({
    required this.key,
    this.attributes = const {},
    this.trafficType,
  });

  @override
  String toString() => 'Target(key: $key, trafficType: $trafficType)';
}
