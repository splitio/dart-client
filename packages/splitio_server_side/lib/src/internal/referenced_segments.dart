import 'package:splitio_commons/src/models/matchers/user_defined_segment_matcher.dart';
import 'package:splitio_commons/src/models/parsed_split.dart';

/// Collects every user-defined segment name referenced by [splits]'
/// conditions. Used to prime the [SegmentStore] with the segments the
/// [SegmentChangesFetcher] should poll on the next cycle.
///
/// Rule-based segments live in a separate store and are NOT included —
/// only [UserDefinedSegmentMatcher] references (the ones served by
/// `/segmentChanges/{name}`).
Set<String> referencedSegmentsIn(Iterable<ParsedSplit> splits) {
  final names = <String>{};
  for (final split in splits) {
    for (final rule in split.conditions) {
      for (final delegate in rule.matcher.delegates) {
        final inner = delegate.delegate;
        if (inner is UserDefinedSegmentMatcher) {
          names.add(inner.segmentName);
        }
      }
    }
  }
  return names;
}
