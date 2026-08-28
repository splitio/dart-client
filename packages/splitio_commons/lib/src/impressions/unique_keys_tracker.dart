import 'dart:collection';

/// Tracks unique matching keys seen per feature for MTK (UniqueKeys) reporting.
class UniqueKeysTracker {
  static const int _maxSize = 30000;

  final Map<String, Set<String>> _data = {};
  final Queue<(String, String)> _insertionOrder = Queue();

  /// Records that [key] was seen evaluating [feature].
  void track(String feature, String key) {
    final isNewPair = _data.putIfAbsent(feature, () => {}).add(key);
    if (!isNewPair) return;

    if (_insertionOrder.length >= _maxSize) {
      final (oldestFeature, oldestKey) = _insertionOrder.removeFirst();
      final oldestSet = _data[oldestFeature];
      oldestSet?.remove(oldestKey);
      if (oldestSet != null && oldestSet.isEmpty) {
        _data.remove(oldestFeature);
      }
    }
    _insertionOrder.add((feature, key));
  }

  /// Returns all accumulated data and clears internal state.
  Map<String, Set<String>> popAll() {
    final copy = Map<String, Set<String>>.from(_data);
    _data.clear();
    _insertionOrder.clear();
    return copy;
  }

  bool get isEmpty => _data.isEmpty;

  void clear() {
    _data.clear();
    _insertionOrder.clear();
  }
}
