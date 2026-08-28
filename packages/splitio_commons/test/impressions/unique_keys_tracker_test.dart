import 'package:splitio_commons/src/impressions/unique_keys_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('UniqueKeysTracker', () {
    test('track accumulates keys per feature', () {
      final tracker = UniqueKeysTracker();

      tracker.track('feat_a', 'user1');
      tracker.track('feat_a', 'user2');

      final data = tracker.popAll();
      expect(data['feat_a'], containsAll(['user1', 'user2']));
    });

    test('popAll returns correct grouped data and clears internal state', () {
      final tracker = UniqueKeysTracker();

      tracker.track('feat', 'key1');
      final first = tracker.popAll();
      expect(first['feat'], contains('key1'));

      final second = tracker.popAll();
      expect(second, isEmpty);
    });

    test('multiple keys for same feature all appear in set', () {
      final tracker = UniqueKeysTracker();

      tracker.track('feat', 'k1');
      tracker.track('feat', 'k2');
      tracker.track('feat', 'k3');

      final data = tracker.popAll();
      expect(data['feat'], hasLength(3));
    });

    test('multiple features have separate sets', () {
      final tracker = UniqueKeysTracker();

      tracker.track('feat_a', 'user1');
      tracker.track('feat_b', 'user2');

      final data = tracker.popAll();
      expect(data['feat_a'], contains('user1'));
      expect(data['feat_a'], isNot(contains('user2')));
      expect(data['feat_b'], contains('user2'));
    });

    test('duplicate key for same feature is stored only once', () {
      final tracker = UniqueKeysTracker();

      tracker.track('feat', 'user1');
      tracker.track('feat', 'user1');

      final data = tracker.popAll();
      expect(data['feat'], hasLength(1));
    });

    test('isEmpty returns true when no data', () {
      final tracker = UniqueKeysTracker();
      expect(tracker.isEmpty, isTrue);
    });

    test('isEmpty returns false after tracking', () {
      final tracker = UniqueKeysTracker();
      tracker.track('feat', 'key');
      expect(tracker.isEmpty, isFalse);
    });

    test('clear empties the tracker', () {
      final tracker = UniqueKeysTracker();
      tracker.track('feat', 'key');
      tracker.clear();
      expect(tracker.isEmpty, isTrue);
    });

    test('respects max size cap of 30000, evicting oldest pair', () {
      final tracker = UniqueKeysTracker();
      for (var i = 0; i < 30000; i++) {
        tracker.track('feat$i', 'key$i');
      }
      tracker.track('feat_overflow', 'key_overflow');

      final data = tracker.popAll();
      final totalPairs =
          data.values.fold<int>(0, (sum, keys) => sum + keys.length);
      expect(totalPairs, 30000);
      expect(data['feat0'], isNot(contains('key0')));
      expect(data['feat_overflow'], contains('key_overflow'));
    });

    test('re-tracking an existing pair does not trigger eviction', () {
      final tracker = UniqueKeysTracker();
      for (var i = 0; i < 30000; i++) {
        tracker.track('feat$i', 'key$i');
      }
      tracker.track('feat0', 'key0');

      final data = tracker.popAll();
      expect(data['feat0'], contains('key0'));
      final totalPairs =
          data.values.fold<int>(0, (sum, keys) => sum + keys.length);
      expect(totalPairs, 30000);
    });
  });
}
