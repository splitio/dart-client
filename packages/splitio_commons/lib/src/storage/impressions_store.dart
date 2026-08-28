import 'dart:collection';

import 'package:splitio_commons/src/models/models.dart';

abstract interface class ImpressionsStore {
  void push(KeyImpression impression);
  void pushAll(List<KeyImpression> impressions);
  List<KeyImpression> popAll();
  int get count;
  bool get isEmpty;
  void clear();
}

class InMemoryImpressionsStore implements ImpressionsStore {
  static const int _maxSize = 30000;
  final Queue<KeyImpression> _queue = Queue();

  @override
  void push(KeyImpression impression) {
    if (_queue.length >= _maxSize) {
      _queue.removeFirst();
    }
    _queue.add(impression);
  }

  @override
  void pushAll(List<KeyImpression> impressions) {
    for (final imp in impressions) {
      push(imp);
    }
  }

  @override
  List<KeyImpression> popAll() {
    final result = _queue.toList();
    _queue.clear();
    return result;
  }

  @override
  int get count => _queue.length;

  @override
  bool get isEmpty => _queue.isEmpty;

  @override
  void clear() => _queue.clear();
}
