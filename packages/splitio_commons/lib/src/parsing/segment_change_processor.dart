import 'package:splitio_commons/src/storage/storage.dart';

/// Consumes `/segmentChanges/{name}` payloads and writes them into a
/// [SegmentStore]. The payload shape is
/// `{"name": String, "added": List<String>, "removed": List<String>,
/// "since": int, "till": int}`.
///
/// Server-side analog of [MembershipsProcessor]: same shape of
/// contract (payload → store), different payload and store.
class SegmentChangeProcessor {
  final SegmentStore _store;

  SegmentChangeProcessor({required SegmentStore store}) : _store = store;

  /// Applies the change to the store and returns the `till` cursor of the
  /// applied payload plus whether it added or removed at least one member,
  /// or `null` when the payload is malformed (missing `name` or `till`).
  SegmentChangeResult? processSegmentChange(Map<String, dynamic> response) {
    final name = response['name'];
    final till = response['till'];
    if (name is! String || till is! int) return null;

    final added = _stringList(response['added']);
    final removed = _stringList(response['removed']);

    final changed = _store.update(name, added, removed, till);
    return SegmentChangeResult(till: till, changed: changed);
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList(growable: false);
  }
}

/// Result of applying a single `/segmentChanges/{name}` response (spec
/// §4.6/§8.2): [till] is the new cursor; [changed] is whether at least one
/// member was added or removed (used to drive `whenUpdated()`).
class SegmentChangeResult {
  final int till;
  final bool changed;

  const SegmentChangeResult({required this.till, required this.changed});
}
