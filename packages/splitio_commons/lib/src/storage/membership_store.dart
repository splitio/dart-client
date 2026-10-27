import 'package:splitio_commons/src/storage/segment_membership_resolver.dart';

class MembershipChange {
  final int changeNumber;
  final Set<String> mySegments;
  final Set<String> largeSegments;

  const MembershipChange({
    required this.changeNumber,
    required this.mySegments,
    required this.largeSegments,
  });
}

abstract interface class MembershipStore {
  /// Applies [change] for [key] and returns whether it actually changed the
  /// key's mySegments or largeSegments set compared to what was stored
  /// before (used to drive `whenUpdated()`, spec §4.6/§8.2). A first-ever
  /// application for an unknown key is a change only if either set is
  /// non-empty. MUST NOT throw.
  bool applyMembership(String key, MembershipChange change);
  bool isInSegment(String segmentName, String key);
  bool hasKey(String key);
  int changeNumber(String key);
  void clear(String key);

  /// The key's current mySegments (MS) set, or an empty set when the key is
  /// unknown. Used by in-place membership updates (spec §12.2 KEY_LIST /
  /// SEGMENT_REMOVAL) that must edit one locus while preserving the other.
  Set<String> mySegmentsForKey(String key);

  /// The key's current largeSegments (LS) set, or an empty set when the key is
  /// unknown. LS is CS-only (spec §12.2).
  Set<String> largeSegmentsForKey(String key);
}

class InMemoryMembershipStore
    implements MembershipStore, SegmentMembershipResolver {
  final Map<String, _KeyMembership> _memberships = {};

  @override
  bool applyMembership(String key, MembershipChange change) {
    final previous = _memberships[key];
    _memberships[key] = _KeyMembership(
      changeNumber: change.changeNumber,
      mySegments: {...change.mySegments},
      largeSegments: {...change.largeSegments},
    );
    if (previous == null) {
      return change.mySegments.isNotEmpty || change.largeSegments.isNotEmpty;
    }
    return !_setEquals(previous.mySegments, change.mySegments) ||
        !_setEquals(previous.largeSegments, change.largeSegments);
  }

  @override
  bool isInSegment(String segmentName, String key) {
    final membership = _memberships[key];
    if (membership == null) return false;
    return membership.mySegments.contains(segmentName) ||
        membership.largeSegments.contains(segmentName);
  }

  @override
  bool hasKey(String key) => _memberships.containsKey(key);

  @override
  int changeNumber(String key) {
    return _memberships[key]?.changeNumber ?? -1;
  }

  @override
  void clear(String key) {
    _memberships.remove(key);
  }

  @override
  Set<String> mySegmentsForKey(String key) =>
      {...?_memberships[key]?.mySegments};

  @override
  Set<String> largeSegmentsForKey(String key) =>
      {...?_memberships[key]?.largeSegments};
}

bool _setEquals(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

class _KeyMembership {
  final int changeNumber;
  final Set<String> mySegments;
  final Set<String> largeSegments;

  const _KeyMembership({
    required this.changeNumber,
    required this.mySegments,
    required this.largeSegments,
  });
}
