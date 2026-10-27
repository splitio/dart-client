import 'package:splitio_commons/src/storage/membership_store.dart';
import 'package:splitio_commons/src/storage/segment_membership_resolver.dart';
import 'package:test/test.dart';

class _FakeResolver implements SegmentMembershipResolver {
  final Map<String, Set<String>> _members;
  _FakeResolver(this._members);

  @override
  bool isInSegment(String segmentName, String key) =>
      _members[segmentName]?.contains(key) ?? false;
}

void main() {
  group('SegmentMembershipResolver', () {
    test('exposes a single isInSegment method that returns bool', () {
      final SegmentMembershipResolver r = _FakeResolver({
        'seg-a': {'user-1', 'user-2'},
      });
      expect(r.isInSegment('seg-a', 'user-1'), isTrue);
      expect(r.isInSegment('seg-a', 'user-9'), isFalse);
      expect(r.isInSegment('seg-missing', 'user-1'), isFalse);
    });
  });

  group('InMemoryMembershipStore implements SegmentMembershipResolver', () {
    test('behaves identically through the interface', () {
      final store = InMemoryMembershipStore();
      store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 1,
          mySegments: {'seg-a'},
          largeSegments: {},
        ),
      );

      final SegmentMembershipResolver r = store;
      expect(r.isInSegment('seg-a', 'user-1'), isTrue);
      expect(r.isInSegment('seg-a', 'user-2'), isFalse);
      expect(r.isInSegment('seg-b', 'user-1'), isFalse);
    });
  });

  // `applyMembership`'s bool return drives `whenUpdated()` (spec §4.6/§8.2):
  // it MUST report whether the key's mySegments/largeSegments actually
  // changed, not just that the store was written to.
  group('InMemoryMembershipStore.applyMembership change detection', () {
    test('first-ever application with non-empty segments is a change', () {
      final store = InMemoryMembershipStore();
      final changed = store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 1,
          mySegments: {'seg-a'},
          largeSegments: {},
        ),
      );
      expect(changed, isTrue);
    });

    test('first-ever application with empty segments is not a change', () {
      final store = InMemoryMembershipStore();
      final changed = store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 1,
          mySegments: {},
          largeSegments: {},
        ),
      );
      expect(changed, isFalse);
    });

    test('re-delivering the identical membership set is not a change', () {
      final store = InMemoryMembershipStore();
      store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 1,
          mySegments: {'seg-a'},
          largeSegments: {'seg-b'},
        ),
      );
      final changed = store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 2,
          mySegments: {'seg-a'},
          largeSegments: {'seg-b'},
        ),
      );
      expect(changed, isFalse);
    });

    test('adding a mySegments key is a change', () {
      final store = InMemoryMembershipStore();
      store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 1,
          mySegments: {'seg-a'},
          largeSegments: {},
        ),
      );
      final changed = store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 2,
          mySegments: {'seg-a', 'seg-c'},
          largeSegments: {},
        ),
      );
      expect(changed, isTrue);
    });

    test('removing a mySegments key is a change', () {
      final store = InMemoryMembershipStore();
      store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 1,
          mySegments: {'seg-a'},
          largeSegments: {},
        ),
      );
      final changed = store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 2,
          mySegments: {},
          largeSegments: {},
        ),
      );
      expect(changed, isTrue);
    });

    test('a largeSegments-only diff is also a change', () {
      final store = InMemoryMembershipStore();
      store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 1,
          mySegments: {'seg-a'},
          largeSegments: {},
        ),
      );
      final changed = store.applyMembership(
        'user-1',
        const MembershipChange(
          changeNumber: 2,
          mySegments: {'seg-a'},
          largeSegments: {'seg-ls'},
        ),
      );
      expect(changed, isTrue);
    });
  });
}
