import 'package:splitio_commons/src/sync/streaming/sync_delay_calculator.dart';
import 'package:test/test.dart';

void main() {
  const calc = SyncDelayCalculator();

  group('no delay cases', () {
    test('hashingAlgorithm NONE -> 0', () {
      expect(
        calc.delayMs(
          matchingKey: 'user@example.com',
          strategy: MembershipStrategy.unbounded,
          h: HashingAlgorithm.none,
          i: 5000,
        ),
        0,
      );
    });

    test('keyList strategy -> 0 (not a fetch notification)', () {
      expect(
        calc.delayMs(
          matchingKey: 'user@example.com',
          strategy: MembershipStrategy.keyList,
          h: HashingAlgorithm.murmur3_32,
          i: 5000,
        ),
        0,
      );
    });

    test('segmentRemoval strategy -> 0', () {
      expect(
        calc.delayMs(
          matchingKey: 'user@example.com',
          strategy: MembershipStrategy.segmentRemoval,
          i: 5000,
        ),
        0,
      );
    });
  });

  group('delay computation (validated against reference murmur3_32)', () {
    // murmurhash3X8632('user@example.com', 0) == 1104125020 (reference).
    test('unbounded, default seed 0', () {
      const hash = 1104125020;
      final expected = hash % 5000;
      expect(
        calc.delayMs(
          matchingKey: 'user@example.com',
          strategy: MembershipStrategy.unbounded,
          i: 5000,
          s: 0,
        ),
        expected,
      );
    });

    test('bounded, non-zero seed changes the delay', () {
      // seed 12345 -> hash 2559733472.
      const hash = 2559733472;
      final expected = hash % 5000;
      expect(
        calc.delayMs(
          matchingKey: 'user@example.com',
          strategy: MembershipStrategy.bounded,
          i: 5000,
          s: 12345,
        ),
        expected,
      );
    });

    test('null seed defaults to 0', () {
      const hash = 1104125020;
      final withNull = calc.delayMs(
        matchingKey: 'user@example.com',
        strategy: MembershipStrategy.unbounded,
        i: 5000,
      );
      final withZero = calc.delayMs(
        matchingKey: 'user@example.com',
        strategy: MembershipStrategy.unbounded,
        i: 5000,
        s: 0,
      );
      expect(withNull, hash % 5000);
      expect(withNull, withZero);
    });
  });

  group('interval defaulting', () {
    test('null interval -> default 60000', () {
      const hash = 1104125020;
      expect(
        calc.delayMs(
          matchingKey: 'user@example.com',
          strategy: MembershipStrategy.unbounded,
        ),
        hash % 60000,
      );
    });

    test('zero interval -> default 60000', () {
      const hash = 1104125020;
      expect(
        calc.delayMs(
          matchingKey: 'user@example.com',
          strategy: MembershipStrategy.unbounded,
          i: 0,
        ),
        hash % 60000,
      );
    });

    test('negative interval -> default 60000', () {
      const hash = 1104125020;
      expect(
        calc.delayMs(
          matchingKey: 'user@example.com',
          strategy: MembershipStrategy.unbounded,
          i: -10,
        ),
        hash % 60000,
      );
    });
  });

  group('invariants', () {
    test('delay always within [0, i)', () {
      for (final key in ['alice', 'bob', 'carol', 'user@example.com', 'x']) {
        for (final interval in [1, 100, 5000, 60000]) {
          final d = calc.delayMs(
            matchingKey: key,
            strategy: MembershipStrategy.unbounded,
            i: interval,
            s: 7,
          );
          expect(d, greaterThanOrEqualTo(0));
          expect(d, lessThan(interval));
        }
      }
    });

    test('deterministic per key + seed', () {
      final a = calc.delayMs(
        matchingKey: 'alice',
        strategy: MembershipStrategy.unbounded,
        i: 5000,
        s: 3,
      );
      final b = calc.delayMs(
        matchingKey: 'alice',
        strategy: MembershipStrategy.unbounded,
        i: 5000,
        s: 3,
      );
      expect(a, b);
    });
  });
}
