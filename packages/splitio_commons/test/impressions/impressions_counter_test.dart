import 'package:splitio_commons/src/impressions/impressions_counter.dart';
import 'package:test/test.dart';

void main() {
  group('ImpressionsCounter', () {
    test('starts empty', () {
      final counter = ImpressionsCounter();
      expect(counter.isEmpty, isTrue);
    });

    test('record accumulates counts truncated to the hour', () {
      final counter = ImpressionsCounter();
      counter.record('feat', 3600000);
      counter.record('feat', 3600500);

      final data = counter.popAll();
      expect(data['feat::3600000'], 2);
    });

    test('popAll clears internal state', () {
      final counter = ImpressionsCounter();
      counter.record('feat', 0);
      counter.popAll();
      expect(counter.isEmpty, isTrue);
    });

    test('clear empties the counter', () {
      final counter = ImpressionsCounter();
      counter.record('feat', 0);
      counter.clear();
      expect(counter.isEmpty, isTrue);
    });

    test('respects max size cap of 30000, evicting oldest entry', () {
      final counter = ImpressionsCounter();
      for (var i = 0; i < 30000; i++) {
        counter.record('feat$i', 0);
      }
      // one more distinct key beyond the cap should evict the oldest
      counter.record('feat_overflow', 0);

      final data = counter.popAll();
      expect(data.length, 30000);
      expect(data.containsKey('feat0::0'), isFalse);
      expect(data.containsKey('feat_overflow::0'), isTrue);
    });

    test('re-incrementing an existing key does not trigger eviction', () {
      final counter = ImpressionsCounter();
      for (var i = 0; i < 30000; i++) {
        counter.record('feat$i', 0);
      }
      counter.record('feat0', 0);

      final data = counter.popAll();
      expect(data.length, 30000);
      expect(data['feat0::0'], 2);
    });
  });
}
