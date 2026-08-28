import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:test/test.dart';

void main() {
  group('MembershipsProcessor', () {
    late InMemoryMembershipStore store;
    late MembershipsProcessor processor;

    setUp(() {
      store = InMemoryMembershipStore();
      processor = MembershipsProcessor(membershipStore: store);
    });

    test('processes standard segments (ms)', () {
      final response = {
        'ms': {
          'k': ['segment_a', 'segment_b'],
          'cn': 50,
        },
      };

      processor.processMemberships(response, 'user1');

      expect(store.isInSegment('segment_a', 'user1'), isTrue);
      expect(store.isInSegment('segment_b', 'user1'), isTrue);
      expect(store.isInSegment('segment_c', 'user1'), isFalse);
      expect(store.changeNumber('user1'), equals(50));
    });

    test('processes large segments (ls)', () {
      final response = {
        'ls': {
          'k': ['large_seg_1', 'large_seg_2'],
          'cn': 30,
        },
      };

      processor.processMemberships(response, 'user1');

      expect(store.isInSegment('large_seg_1', 'user1'), isTrue);
      expect(store.isInSegment('large_seg_2', 'user1'), isTrue);
    });

    test('processes both ms and ls together', () {
      final response = {
        'ms': {
          'k': ['seg_a'],
          'cn': 10,
        },
        'ls': {
          'k': ['large_seg_1'],
          'cn': 20,
        },
      };

      processor.processMemberships(response, 'user1');

      expect(store.isInSegment('seg_a', 'user1'), isTrue);
      expect(store.isInSegment('large_seg_1', 'user1'), isTrue);
    });

    test('handles empty segments list', () {
      final response = {
        'ms': {
          'k': <String>[],
          'cn': 0,
        },
      };

      processor.processMemberships(response, 'user1');

      expect(store.isInSegment('anything', 'user1'), isFalse);
    });

    test('handles missing ms and ls keys', () {
      final response = <String, dynamic>{};

      processor.processMemberships(response, 'user1');

      expect(store.isInSegment('anything', 'user1'), isFalse);
    });

    test('processes memberships for different keys independently', () {
      final response1 = {
        'ms': {
          'k': ['seg_a'],
          'cn': 10,
        },
      };
      final response2 = {
        'ms': {
          'k': ['seg_b'],
          'cn': 20,
        },
      };

      processor.processMemberships(response1, 'user1');
      processor.processMemberships(response2, 'user2');

      expect(store.isInSegment('seg_a', 'user1'), isTrue);
      expect(store.isInSegment('seg_b', 'user1'), isFalse);
      expect(store.isInSegment('seg_b', 'user2'), isTrue);
      expect(store.isInSegment('seg_a', 'user2'), isFalse);
    });

    test('uses ms changeNumber when ls is absent', () {
      final response = {
        'ms': {
          'k': ['seg_a'],
          'cn': 42,
        },
      };

      processor.processMemberships(response, 'user1');

      expect(store.changeNumber('user1'), equals(42));
    });

    test('parses ms segments as {"n": "..."} objects', () {
      final response = {
        'ms': {
          'k': [
            {'n': 'segment_a'},
            {'n': 'segment_b'},
          ],
          'cn': 5,
        },
      };

      processor.processMemberships(response, 'user1');

      expect(store.isInSegment('segment_a', 'user1'), isTrue);
      expect(store.isInSegment('segment_b', 'user1'), isTrue);
      expect(store.changeNumber('user1'), equals(5));
    });

    test('parses ls segments as {"n": "..."} objects', () {
      final response = {
        'ls': {
          'k': [
            {'n': 'large_1'},
          ],
          'cn': 9,
        },
      };

      processor.processMemberships(response, 'user1');

      expect(store.isInSegment('large_1', 'user1'), isTrue);
    });

    test('supports mixed bare-string and object segment entries', () {
      final response = {
        'ms': {
          'k': [
            'legacy_seg',
            {'n': 'new_seg'},
          ],
          'cn': 7,
        },
      };

      processor.processMemberships(response, 'user1');

      expect(store.isInSegment('legacy_seg', 'user1'), isTrue);
      expect(store.isInSegment('new_seg', 'user1'), isTrue);
    });
  });
}
