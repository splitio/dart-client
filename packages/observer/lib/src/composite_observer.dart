import 'observable_event.dart';
import 'observer.dart';
import 'observer_registry.dart';

final class CompositeObserver implements Observer, ObserverRegistry {
  final List<Observer> _observers = [];

  @override
  void register(Observer observer) {
    if (!_observers.contains(observer)) {
      _observers.add(observer);
    }
  }

  @override
  void unregister(Observer observer) {
    _observers.remove(observer);
  }

  @override
  void unregisterAll() {
    _observers.clear();
  }

  @override
  void notifyEvent(ObservableEvent event) {
    // Snapshot so registrations during dispatch don't cause issues.
    final snapshot = List<Observer>.from(_observers);
    for (final observer in snapshot) {
      try {
        observer.notifyEvent(event);
      } catch (_) {
        // Fault isolation: swallow exception so remaining observers still receive.
      }
    }
  }
}
