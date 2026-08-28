import 'dart:collection';

import 'event.dart';

abstract interface class EventsStore {
  bool push(Event event, int size);
  List<Event> popAll();
  int get count;
  bool get isEmpty;
  void setOnFullQueue(void Function() cb);
  void clear();
}

class InMemoryEventsStore implements EventsStore {
  static const int _maxQueueBytes = 5 * 1024 * 1024;
  static const int _maxQueueLength = 5000;

  final Queue<Event> _queue = Queue();
  int _queueBytes = 0;
  void Function()? _onFullQueue;

  @override
  bool push(Event event, int size) {
    _queue.add(event);
    _queueBytes += size;
    if (_queueBytes >= _maxQueueBytes || _queue.length >= _maxQueueLength) {
      _onFullQueue?.call();
    }
    return true;
  }

  @override
  List<Event> popAll() {
    final result = _queue.toList();
    _queue.clear();
    _queueBytes = 0;
    return result;
  }

  @override
  int get count => _queue.length;

  @override
  bool get isEmpty => _queue.isEmpty;

  @override
  void setOnFullQueue(void Function() cb) {
    _onFullQueue = cb;
  }

  @override
  void clear() {
    _queue.clear();
    _queueBytes = 0;
  }
}
