import 'observer.dart';

abstract interface class ObserverRegistry {
  void register(Observer observer);
  void unregister(Observer observer);
  void unregisterAll();
}
