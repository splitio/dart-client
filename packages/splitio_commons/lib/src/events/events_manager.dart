import 'dart:async';

class EventsManager {
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _timeout = Completer<void>();
  final StreamController<List<String>> _updates =
      StreamController<List<String>>.broadcast();
  bool _disposed = false;

  Future<void> get onReady => _ready.future;
  Future<void> get onTimeout => _timeout.future;
  Stream<List<String>> get onUpdated => _updates.stream;

  bool get isReady => _ready.isCompleted;
  bool get isDestroyed => _disposed;

  void notifyReady() {
    if (_disposed || _ready.isCompleted) return;
    _ready.complete();
  }

  void notifyTimeout() {
    if (_disposed || _timeout.isCompleted) return;
    _timeout.complete();
  }

  void notifyUpdate(List<String> changedFlags) {
    if (_disposed) return;
    _updates.add(List.unmodifiable(changedFlags));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_ready.isCompleted) _ready.complete();
    if (!_timeout.isCompleted) _timeout.complete();
    await _updates.close();
  }
}
