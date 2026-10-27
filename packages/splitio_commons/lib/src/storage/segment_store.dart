import 'package:splitio_commons/src/storage/segment_membership_resolver.dart';

/// Server-side segment storage.
///
/// Sits on the opposite axis from [MembershipStore]: server-side keeps a
/// **segment → member-keys** map (populated from `/segmentChanges/{name}`),
/// where CS keeps a **key → segment-names** map. Both answer the same
/// evaluation-time question — "is this key in this segment?" — behind the
/// shared [SegmentMembershipResolver] seam.
abstract interface class SegmentStore implements SegmentMembershipResolver {
  /// Applies an incremental change for [name]. Returns true when at least
  /// one add or remove modified the member set; a cursor-only advance
  /// returns false. MUST NOT throw.
  bool update(
    String name,
    List<String> addedKeys,
    List<String> removedKeys,
    int changeNumber,
  );

  /// Latest applied cursor for [name], or `-1` when the segment is unknown.
  /// MUST NOT throw.
  int changeNumber(String name);

  /// Registers empty slots for [names]. Used when the flag parser discovers
  /// a segment reference before the fetcher has seen it, so
  /// [getRegisteredSegments] can drive the next poll cycle without a race.
  /// Existing members and cursors are preserved.
  void registerSegments(Iterable<String> names);

  /// Every segment name currently tracked, including empty ones registered
  /// via [registerSegments] but not yet fetched.
  Iterable<String> getRegisteredSegments();

  /// True iff every segment currently tracked (per [getRegisteredSegments])
  /// has had at least one successful `/segmentChanges` response applied via
  /// [update] — i.e. its [changeNumber] has actually been set, not merely
  /// defaulted to `-1`. A segment registered via [registerSegments] but
  /// never fetched yet makes this `false`.
  ///
  /// Mirrors the JS SDK's `checkAllSegmentsExist` (splitChangesUpdater.ts).
  /// Used to gate SDK_READY so a feature flag that just registered a
  /// brand-new segment can't let readiness fire before that segment's
  /// membership data has actually arrived (spec §8.2). MUST NOT throw.
  bool allRegisteredSegmentsFetched();

  /// Clears every segment, its members, and its cursor.
  void clear();
}

/// Default in-memory implementation. Backed by `Map<String, Set<String>>`
/// for members and `Map<String, int>` for per-segment cursors.
class InMemorySegmentStore implements SegmentStore {
  final Map<String, Set<String>> _members = {};
  final Map<String, int> _changeNumbers = {};

  @override
  bool isInSegment(String segmentName, String key) {
    final members = _members[segmentName];
    if (members == null) return false;
    return members.contains(key);
  }

  @override
  bool update(
    String name,
    List<String> addedKeys,
    List<String> removedKeys,
    int changeNumber,
  ) {
    final members = _members.putIfAbsent(name, () => <String>{});
    var changed = false;
    for (final key in addedKeys) {
      changed = members.add(key) || changed;
    }
    for (final key in removedKeys) {
      changed = members.remove(key) || changed;
    }
    _changeNumbers[name] = changeNumber;
    return changed;
  }

  @override
  int changeNumber(String name) => _changeNumbers[name] ?? -1;

  @override
  void registerSegments(Iterable<String> names) {
    for (final name in names) {
      _members.putIfAbsent(name, () => <String>{});
    }
  }

  @override
  Iterable<String> getRegisteredSegments() => _members.keys;

  @override
  bool allRegisteredSegmentsFetched() =>
      _members.keys.every((name) => _changeNumbers.containsKey(name));

  @override
  void clear() {
    _members.clear();
    _changeNumbers.clear();
  }
}
