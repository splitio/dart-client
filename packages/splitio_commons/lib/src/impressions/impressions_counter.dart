class ImpressionsCounter {
  static const int _maxSize = 30000;

  final Map<String, int> _counts = {};

  void record(String feature, int timestamp) {
    final truncatedHour = (timestamp ~/ 3600000) * 3600000;
    final key = '$feature::$truncatedHour';
    if (_counts.length >= _maxSize && !_counts.containsKey(key)) {
      _counts.remove(_counts.keys.first);
    }
    _counts[key] = (_counts[key] ?? 0) + 1;
  }

  Map<String, int> popAll() {
    final result = Map<String, int>.from(_counts);
    _counts.clear();
    return result;
  }

  bool get isEmpty => _counts.isEmpty;

  void clear() => _counts.clear();
}
