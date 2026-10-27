import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_server_side/src/internal/referenced_segments.dart';
import 'package:test/test.dart';

ParsedSplit _splitWithSegments(List<String> segmentNames) {
  return ParsedSplit(
    name: 'flag',
    trafficTypeName: 'user',
    killed: false,
    defaultTreatment: 'off',
    conditions: [
      TargetingRule(
        conditionType: ConditionType.rollout,
        matcher: CombiningMatcher(
          delegates: [
            for (final s in segmentNames)
              AttributeMatcher(
                delegate: UserDefinedSegmentMatcher(segmentName: s),
              ),
          ],
        ),
        partitions: const [],
        label: 'in segment',
      ),
    ],
    trafficAllocation: 100,
    seed: 0,
    algo: 2,
    changeNumber: 1,
  );
}

void main() {
  group('referencedSegmentsIn', () {
    test('empty input yields empty set', () {
      expect(referencedSegmentsIn(const <ParsedSplit>[]), isEmpty);
    });

    test('extracts segments from UserDefinedSegmentMatcher in delegates', () {
      final splits = [
        _splitWithSegments(['employees']),
        _splitWithSegments(['betas', 'employees']),
      ];
      expect(
          referencedSegmentsIn(splits), equals(<String>{'employees', 'betas'}));
    });

    test('ignores non-segment matchers', () {
      final split = ParsedSplit(
        name: 'flag',
        trafficTypeName: 'user',
        killed: false,
        defaultTreatment: 'off',
        conditions: const [],
        trafficAllocation: 100,
        seed: 0,
        algo: 2,
        changeNumber: 1,
      );
      expect(referencedSegmentsIn([split]), isEmpty);
    });
  });
}
