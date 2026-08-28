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
  void applyMembership(String key, MembershipChange change);
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

class InMemoryMembershipStore implements MembershipStore {
  final Map<String, _KeyMembership> _memberships = {};

  @override
  void applyMembership(String key, MembershipChange change) {
    _memberships[key] = _KeyMembership(
      changeNumber: change.changeNumber,
      mySegments: {...change.mySegments},
      largeSegments: {...change.largeSegments},
    );
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
