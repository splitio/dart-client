final class Event {
  final String eventTypeId;
  final String trafficTypeName;
  final String key;
  final int timestamp;
  final double? value;
  final Map<String, Object?>? properties;

  const Event({
    required this.eventTypeId,
    required this.trafficTypeName,
    required this.key,
    required this.timestamp,
    this.value,
    this.properties,
  });

  Map<String, Object?> toJson() => {
        'eventTypeId': eventTypeId,
        'trafficTypeName': trafficTypeName,
        'key': key,
        'timestamp': timestamp,
        if (value != null) 'value': value,
        if (properties != null) 'properties': properties,
      };
}
