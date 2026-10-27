import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_server_side/src/internal/flags_segment_sync.dart';
import 'package:test/test.dart';

ParsedSplit _splitReferencing(String segmentName) {
  return ParsedSplit(
    name: 'flag_with_segment',
    trafficTypeName: 'user',
    killed: false,
    defaultTreatment: 'off',
    trafficAllocation: 100,
    trafficAllocationSeed: 1,
    seed: 2,
    changeNumber: 1000,
    algo: 2,
    conditions: [
      TargetingRule(
        conditionType: ConditionType.rollout,
        label: 'in segment $segmentName',
        matcher: CombiningMatcher(
          combiner: CombinerEnum.and,
          delegates: [
            AttributeMatcher(
              negate: false,
              delegate: UserDefinedSegmentMatcher(segmentName: segmentName),
            ),
          ],
        ),
        partitions: const [Partition(treatment: 'on', size: 100)],
      ),
    ],
    configurations: const {},
    sets: const [],
  );
}

void main() {
  group('FlagsSegmentSync.onFlagsChanged', () {
    test('fetches segments immediately when a new segment is registered',
        () async {
      final ruleStore = InMemoryRuleStore();
      final segmentStore = InMemorySegmentStore();
      var fetchCalls = 0;
      final sync = FlagsSegmentSync(
        ruleStore: ruleStore,
        segmentStore: segmentStore,
        fetchSegments: () async {
          fetchCalls++;
          return true;
        },
        logger: SplitLogger(level: LogLevel.none),
      );

      ruleStore.applyChange(Change(changeNumber: 1000, updates: {
        'flag_with_segment': _splitReferencing('beta_users'),
      }));

      sync.onFlagsChanged();
      // The fetch is fired unawaited; give the microtask queue a turn.
      await Future<void>.delayed(Duration.zero);

      expect(fetchCalls, equals(1));
      expect(segmentStore.getRegisteredSegments(), contains('beta_users'));
    });

    test('does not fetch when the flags change registers nothing new',
        () async {
      final ruleStore = InMemoryRuleStore();
      final segmentStore = InMemorySegmentStore();
      // 'beta_users' is already registered AND already fetched.
      segmentStore.update('beta_users', const [], const [], 1);
      var fetchCalls = 0;
      final sync = FlagsSegmentSync(
        ruleStore: ruleStore,
        segmentStore: segmentStore,
        fetchSegments: () async {
          fetchCalls++;
          return true;
        },
        logger: SplitLogger(level: LogLevel.none),
      );

      ruleStore.applyChange(Change(changeNumber: 1000, updates: {
        'flag_with_segment': _splitReferencing('beta_users'),
      }));

      sync.onFlagsChanged();
      await Future<void>.delayed(Duration.zero);

      expect(fetchCalls, equals(0),
          reason: 'beta_users was already a known, registered segment — '
              'this flags change did not reference anything new, so no '
              'extra fetch is owed. The periodic segments poll already '
              'owns refreshing it.');
    });

    test('does not fetch on a flags change with no segment references',
        () async {
      final ruleStore = InMemoryRuleStore();
      final segmentStore = InMemorySegmentStore();
      var fetchCalls = 0;
      final sync = FlagsSegmentSync(
        ruleStore: ruleStore,
        segmentStore: segmentStore,
        fetchSegments: () async {
          fetchCalls++;
          return true;
        },
        logger: SplitLogger(level: LogLevel.none),
      );

      sync.onFlagsChanged();
      await Future<void>.delayed(Duration.zero);

      expect(fetchCalls, equals(0));
      expect(segmentStore.getRegisteredSegments(), isEmpty);
    });

    test('a failing immediate fetch is caught and logged, never thrown',
        () async {
      final ruleStore = InMemoryRuleStore();
      final segmentStore = InMemorySegmentStore();
      final sync = FlagsSegmentSync(
        ruleStore: ruleStore,
        segmentStore: segmentStore,
        fetchSegments: () => Future<bool>.error(Exception('network error')),
        logger: SplitLogger(level: LogLevel.none),
      );

      ruleStore.applyChange(Change(changeNumber: 1000, updates: {
        'flag_with_segment': _splitReferencing('beta_users'),
      }));

      expect(() => sync.onFlagsChanged(), returnsNormally);
      await Future<void>.delayed(Duration.zero);
    });

    // Review finding: FlagsSegmentSync.onFlagsChanged MUST NOT start a new
    // segments fetch once the factory has been destroyed — no HTTP may
    // originate from it after destroy() completes.
    test('does not fetch once destroy() has been called', () async {
      final ruleStore = InMemoryRuleStore();
      final segmentStore = InMemorySegmentStore();
      var fetchCalls = 0;
      final sync = FlagsSegmentSync(
        ruleStore: ruleStore,
        segmentStore: segmentStore,
        fetchSegments: () async {
          fetchCalls++;
          return true;
        },
        logger: SplitLogger(level: LogLevel.none),
      );

      sync.destroy();

      ruleStore.applyChange(Change(changeNumber: 1000, updates: {
        'flag_with_segment': _splitReferencing('beta_users'),
      }));
      sync.onFlagsChanged();
      await Future<void>.delayed(Duration.zero);

      expect(fetchCalls, equals(0),
          reason: 'onFlagsChanged() MUST return early once destroyed — no '
              'fetch may be started after the factory has been torn down');
      expect(segmentStore.getRegisteredSegments(), isEmpty,
          reason: 'A destroyed sync does no work at all, not just skipping '
              'the fetch — it must not even scan/register segments');
    });

    test('destroy() is idempotent and safe to call before any flags change',
        () async {
      final ruleStore = InMemoryRuleStore();
      final segmentStore = InMemorySegmentStore();
      final sync = FlagsSegmentSync(
        ruleStore: ruleStore,
        segmentStore: segmentStore,
        fetchSegments: () async => true,
        logger: SplitLogger(level: LogLevel.none),
      );

      expect(() {
        sync.destroy();
        sync.destroy();
      }, returnsNormally);
    });
  });
}
