import 'package:splitio_commons/src/event_tracker/event_tracker.dart';
import 'package:test/test.dart';

Event _event(String id) => Event(
      eventTypeId: id,
      trafficTypeName: 'user',
      key: 'user_a',
      timestamp: 1,
    );

void main() {
  group('InMemoryEventsStore', () {
    test('starts empty', () {
      final store = InMemoryEventsStore();
      expect(store.isEmpty, isTrue);
      expect(store.count, 0);
    });

    test('push and popAll', () {
      final store = InMemoryEventsStore();
      expect(store.push(_event('a'), 1024), isTrue);
      expect(store.push(_event('b'), 1024), isTrue);
      expect(store.count, 2);

      final popped = store.popAll();
      expect(popped.map((e) => e.eventTypeId), ['a', 'b']);
      expect(store.isEmpty, isTrue);
    });

    test('fires onFullQueue when byte size threshold is reached', () {
      final store = InMemoryEventsStore();
      const oneKb = 1024;
      const fiveMb = 5 * 1024 * 1024;

      var fired = 0;
      store.setOnFullQueue(() => fired++);

      for (var i = 0; i < fiveMb ~/ oneKb; i++) {
        expect(store.push(_event('e$i'), oneKb), isTrue);
      }

      expect(fired, greaterThanOrEqualTo(1),
          reason: 'callback fires once cumulative size >= 5MB');
      expect(store.push(_event('overflow'), oneKb), isTrue,
          reason: 'events are never dropped, always accepted');
    });

    test('fires onFullQueue when length threshold (5000) is reached', () {
      final store = InMemoryEventsStore();
      var fired = 0;
      store.setOnFullQueue(() => fired++);

      for (var i = 0; i < 5000; i++) {
        store.push(_event('e$i'), 1);
      }

      expect(fired, greaterThanOrEqualTo(1));
      expect(store.count, 5000);
    });

    test('clear empties the queue and resets byte count', () {
      final store = InMemoryEventsStore();
      store.push(_event('a'), 1024);
      store.push(_event('b'), 1024);

      store.clear();

      expect(store.isEmpty, isTrue);
      expect(store.count, 0);
    });
  });
}
