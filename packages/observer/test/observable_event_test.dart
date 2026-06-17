import 'package:test/test.dart';
import 'package:observer/observer.dart';

void main() {
  group('ObservableEvent', () {
    test('stores type, properties, payload, timestamp', () {
      final e = ObservableEvent(
        type: 'MY_EVENT',
        properties: {'key': 'value'},
        payload: 42,
        timestamp: 1000,
      );
      expect(e.type, 'MY_EVENT');
      expect(e.properties, {'key': 'value'});
      expect(e.payload, 42);
      expect(e.timestamp, 1000);
    });

    test('defaults properties to empty map', () {
      final e = ObservableEvent(type: 'X');
      expect(e.properties, isEmpty);
    });

    test('defaults payload to null', () {
      final e = ObservableEvent(type: 'X');
      expect(e.payload, isNull);
    });

    test('timestamp defaults to a positive value', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final e = ObservableEvent(type: 'X');
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(e.timestamp, greaterThanOrEqualTo(before));
      expect(e.timestamp, lessThanOrEqualTo(after));
    });
  });
}
