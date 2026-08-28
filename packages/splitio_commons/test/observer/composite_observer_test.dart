import 'package:test/test.dart';
import 'package:splitio_commons/src/observer/observer.dart';
import 'package:splitio_commons/src/observer/observable_event.dart';
import 'package:splitio_commons/src/observer/composite_observer.dart';

class _RecordingObserver implements Observer {
  final List<ObservableEvent> received = [];

  @override
  void notifyEvent(ObservableEvent event) => received.add(event);
}

class _ThrowingObserver implements Observer {
  @override
  void notifyEvent(ObservableEvent event) => throw StateError('boom');
}

void main() {
  group('CompositeObserver', () {
    late CompositeObserver composite;

    setUp(() => composite = CompositeObserver());

    test('dispatches to a registered observer', () {
      final obs = _RecordingObserver();
      composite.register(obs);

      final event = ObservableEvent(type: 'TEST');
      composite.notifyEvent(event);

      expect(obs.received, [event]);
    });

    test('dispatches to multiple registered observers', () {
      final a = _RecordingObserver();
      final b = _RecordingObserver();
      composite.register(a);
      composite.register(b);

      final event = ObservableEvent(type: 'X');
      composite.notifyEvent(event);

      expect(a.received, [event]);
      expect(b.received, [event]);
    });

    test('does not dispatch to unregistered observer', () {
      final obs = _RecordingObserver();
      composite.register(obs);
      composite.unregister(obs);

      composite.notifyEvent(ObservableEvent(type: 'X'));

      expect(obs.received, isEmpty);
    });

    test('unregisterAll removes all observers', () {
      final a = _RecordingObserver();
      final b = _RecordingObserver();
      composite.register(a);
      composite.register(b);
      composite.unregisterAll();

      composite.notifyEvent(ObservableEvent(type: 'X'));

      expect(a.received, isEmpty);
      expect(b.received, isEmpty);
    });

    test('fault isolation: exception in one observer does not prevent others',
        () {
      final good = _RecordingObserver();
      composite.register(_ThrowingObserver());
      composite.register(good);

      final event = ObservableEvent(type: 'X');
      // Must not throw
      expect(() => composite.notifyEvent(event), returnsNormally);
      expect(good.received, [event]);
    });

    test('no dispatch when no observers registered', () {
      // Just must not throw
      expect(() => composite.notifyEvent(ObservableEvent(type: 'X')),
          returnsNormally);
    });

    test('register is idempotent — same observer registered twice fires once',
        () {
      final obs = _RecordingObserver();
      composite.register(obs);
      composite.register(obs);

      composite.notifyEvent(ObservableEvent(type: 'X'));

      expect(obs.received, hasLength(1));
    });
  });
}
