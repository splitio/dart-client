import 'dart:collection';

class ImpressionsObserver {
  static const _maxSize = 500;
  final LinkedHashMap<String, int> _cache = LinkedHashMap();

  int? testAndSet(String feature, String key, String treatment,
      int changeNumber, String label, int time) {
    final dedupKey = '$feature::$key::$treatment::$changeNumber::$label';
    final previous = _cache[dedupKey];
    _cache.remove(dedupKey);
    _cache[dedupKey] = time;

    if (_cache.length > _maxSize) {
      _cache.remove(_cache.keys.first);
    }

    return previous;
  }
}
