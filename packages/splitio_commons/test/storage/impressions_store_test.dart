import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

KeyImpression _impression(String feature, {int time = 1000}) => KeyImpression(
      feature: feature,
      keyName: 'key1',
      treatment: 'on',
      label: 'default rule',
      changeNumber: 1,
      time: time,
    );

void main() {
  group('InMemoryImpressionsStore', () {
    late InMemoryImpressionsStore store;

    setUp(() {
      store = InMemoryImpressionsStore();
    });

    test('starts empty', () {
      expect(store.isEmpty, isTrue);
      expect(store.count, 0);
      expect(store.popAll(), isEmpty);
    });

    test('push adds impression', () {
      store.push(_impression('feat1'));
      expect(store.count, 1);
      expect(store.isEmpty, isFalse);
    });

    test('pushAll adds multiple impressions', () {
      store.pushAll([_impression('feat1'), _impression('feat2')]);
      expect(store.count, 2);
    });

    test('popAll returns all and clears', () {
      store.push(_impression('feat1'));
      store.push(_impression('feat2'));

      final result = store.popAll();
      expect(result.length, 2);
      expect(result[0].feature, 'feat1');
      expect(result[1].feature, 'feat2');
      expect(store.isEmpty, isTrue);
      expect(store.count, 0);
    });

    test('popAll on empty store returns empty list', () {
      expect(store.popAll(), isEmpty);
    });

    test('respects max size cap of 30000, dropping oldest', () {
      for (var i = 0; i < 30000; i++) {
        store.push(_impression('feat', time: i));
      }
      expect(store.count, 30000);

      store.push(_impression('feat', time: 99999));
      expect(store.count, 30000);

      final result = store.popAll();
      expect(result.first.time, 1);
      expect(result.last.time, 99999);
    });

    test('pushAll respects cap', () {
      for (var i = 0; i < 29999; i++) {
        store.push(_impression('feat', time: i));
      }

      store.pushAll([
        _impression('feat', time: 50000),
        _impression('feat', time: 50001),
      ]);

      expect(store.count, 30000);
      final result = store.popAll();
      expect(result.first.time, 1);
      expect(result.last.time, 50001);
    });

    test('clear empties the queue', () {
      store.pushAll([_impression('feat1'), _impression('feat2')]);
      store.clear();
      expect(store.isEmpty, isTrue);
      expect(store.count, 0);
    });
  });
}
