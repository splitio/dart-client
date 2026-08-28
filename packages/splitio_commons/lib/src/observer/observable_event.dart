final class ObservableEvent {
  final String type;
  final Map<String, String> properties;

  /// Optional opaque payload. Must be an immutable value; mutating this object
  /// from within an [Observer] corrupts dispatch for subsequent observers.
  final Object? payload;
  final int timestamp;

  ObservableEvent({
    required this.type,
    Map<String, String>? properties,
    this.payload,
    int? timestamp,
  })  : properties = Map.unmodifiable(properties ?? const {}),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;
}
