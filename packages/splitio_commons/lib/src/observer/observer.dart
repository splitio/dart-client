import 'observable_event.dart';

abstract interface class Observer {
  void notifyEvent(ObservableEvent event);
}
