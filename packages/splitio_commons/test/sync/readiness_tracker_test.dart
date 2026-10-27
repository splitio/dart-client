import 'package:splitio_commons/src/sync/readiness_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('ReadinessTracker', () {
    test('fires onSynced once every required feed has synced successfully', () {
      var fired = 0;
      final tracker = ReadinessTracker(
        requiredFeeds: const {'flags', 'segments'},
        onSynced: () => fired++,
      );

      tracker.markSynced('flags', true);
      expect(fired, equals(0), reason: 'segments has not synced yet');

      tracker.markSynced('segments', true);
      expect(fired, equals(1));
    });

    test('a failed sync does not fire onSynced', () {
      var fired = 0;
      final tracker = ReadinessTracker(
        requiredFeeds: const {'flags', 'segments'},
        onSynced: () => fired++,
      );

      tracker.markSynced('flags', false);
      tracker.markSynced('segments', false);

      expect(fired, equals(0));
    });

    test(
        'a failed initial sync does not block a later successful sync '
        'from firing onSynced (spec §8.2)', () {
      var fired = 0;
      final tracker = ReadinessTracker(
        requiredFeeds: const {'flags', 'segments'},
        onSynced: () => fired++,
      );

      // Initial sync: flags succeed, segments fail.
      tracker.markSynced('flags', true);
      tracker.markSynced('segments', false);
      expect(fired, equals(0));

      // A later poll succeeds for segments.
      tracker.markSynced('segments', true);
      expect(fired, equals(1));
    });

    test(
        'fires onSynced exactly once even if feeds report success '
        'repeatedly', () {
      var fired = 0;
      final tracker = ReadinessTracker(
        requiredFeeds: const {'flags'},
        onSynced: () => fired++,
      );

      tracker.markSynced('flags', true);
      tracker.markSynced('flags', true);
      tracker.markSynced('flags', true);

      expect(fired, equals(1));
    });

    test('ignores feeds that are not in requiredFeeds', () {
      var fired = 0;
      final tracker = ReadinessTracker(
        requiredFeeds: const {'flags'},
        onSynced: () => fired++,
      );

      tracker.markSynced('unrelated', true);

      expect(fired, equals(0));
    });

    test('a single required feed fires immediately on first success', () {
      var fired = 0;
      final tracker = ReadinessTracker(
        requiredFeeds: const {'rules'},
        onSynced: () => fired++,
      );

      tracker.markSynced('rules', true);

      expect(fired, equals(1));
    });
  });
}
