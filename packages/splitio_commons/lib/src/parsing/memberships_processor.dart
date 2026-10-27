import 'package:splitio_commons/src/storage/storage.dart';

class MembershipsProcessor {
  final MembershipStore _membershipStore;

  MembershipsProcessor({
    required MembershipStore membershipStore,
  }) : _membershipStore = membershipStore;

  /// Applies the response to [key]'s membership and returns whether it
  /// actually changed the key's mySegments or largeSegments set (used to
  /// drive `whenUpdated()`, spec §4.6/§8.2).
  bool processMemberships(
    Map<String, dynamic> response,
    String key,
  ) {
    final ms = response['ms'] as Map<String, dynamic>?;
    final ls = response['ls'] as Map<String, dynamic>?;

    final mySegments = <String>{};
    final largeSegments = <String>{};

    if (ms != null) {
      final keys = ms['k'] as List? ?? [];
      mySegments.addAll(keys.map(_segmentName));
    }
    if (ls != null) {
      final keys = ls['k'] as List? ?? [];
      largeSegments.addAll(keys.map(_segmentName));
    }

    final cn = (ms?['cn'] as int?) ?? (ls?['cn'] as int?) ?? -1;

    return _membershipStore.applyMembership(
      key,
      MembershipChange(
        changeNumber: cn,
        mySegments: mySegments,
        largeSegments: largeSegments,
      ),
    );
  }

  /// Each entry in a memberships `k` array is a segment object of the form
  /// `{"n": "<segment name>"}`. Older/alternate payloads may send the name as a
  /// bare string, so both shapes are supported.
  static String _segmentName(dynamic entry) {
    if (entry is Map) {
      return entry['n'] as String;
    }
    return entry as String;
  }
}
