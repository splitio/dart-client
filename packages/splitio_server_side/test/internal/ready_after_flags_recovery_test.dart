import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/readiness_tracker.dart';
import 'package:splitio_server_side/src/internal/flags_segment_sync.dart';
import 'package:test/test.dart';

/// Reproduces the exact wiring in `ServerDependencyContainer.build` — minus
/// HTTP and timers — to pin the ordering fix at the unit level: "first
/// flags fetch 500 (failed), second flags fetch 200 with a flag using an
/// IN_SEGMENT matcher — READY MUST fire right after that second fetch,
/// without ever waiting on a segments-interval tick."
///
/// No `Timer`/`fake_async` involved: both "polls" are plain, directly
/// awaited calls, so there is no segments-interval tick to wait for in the
/// first place — which is exactly the point. Before the fix,
/// `onFlagsChanged` only registered the segment; nothing in this test
/// would ever have fetched it, so `allRegisteredSegmentsFetched()` (and
/// therefore READY) would never flip. The fix makes `onFlagsChanged`
/// itself responsible for triggering that fetch.
Map<String, dynamic> get _splitChanges200WithSegment => {
      'ff': {
        's': -1,
        't': 1000,
        'd': [
          {
            'name': 'flag_with_segment',
            'trafficTypeName': 'user',
            'killed': false,
            'defaultTreatment': 'off',
            'trafficAllocation': 100,
            'trafficAllocationSeed': 1,
            'seed': 2,
            'changeNumber': 1000,
            'algo': 2,
            'status': 'ACTIVE',
            'conditions': [
              {
                'conditionType': 'ROLLOUT',
                'matcherGroup': {
                  'combiner': 'AND',
                  'matchers': [
                    {
                      'keySelector': null,
                      'matcherType': 'IN_SEGMENT',
                      'negate': false,
                      'userDefinedSegmentMatcherData': {
                        'segmentName': 'beta_users',
                      },
                      'whitelistMatcherData': null,
                      'unaryNumericMatcherData': null,
                      'betweenMatcherData': null,
                      'booleanMatcherData': null,
                      'dependencyMatcherData': null,
                      'stringMatcherData': null,
                    }
                  ],
                },
                'partitions': [
                  {'treatment': 'on', 'size': 100}
                ],
                'label': 'in segment beta_users',
              }
            ],
            'configurations': <String, dynamic>{},
            'sets': <String>[],
          }
        ],
      },
      'rbs': {'s': -1, 't': 1000, 'd': []},
    };

void main() {
  test(
      'READY fires right after the second (successful) flags fetch, with '
      'no segments-interval tick ever running (spec §8.2)', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final segmentStore = InMemorySegmentStore();
    final processor = SplitChangeProcessor(
      parser: RuleParser(),
      ruleStore: ruleStore,
      rbsStore: rbsStore,
    );

    var readyFired = false;
    final readinessTracker = ReadinessTracker(
      requiredFeeds: const {'flags', 'segments'},
      onSynced: () => readyFired = true,
    );

    var segmentsFetchCalls = 0;
    Future<bool> fetchSegments() async {
      segmentsFetchCalls++;
      for (final name in segmentStore.getRegisteredSegments()) {
        segmentStore.update(name, const ['member_key'], const [], 2000);
      }
      readinessTracker.markSynced('segments', true);
      return true;
    }

    final flagsSegmentSync = FlagsSegmentSync(
      ruleStore: ruleStore,
      segmentStore: segmentStore,
      fetchSegments: fetchSegments,
      logger: SplitLogger(level: LogLevel.none),
    );

    // Mirrors ServerDependencyContainer's `tryMarkFlagsArrived` gate.
    var flagsFetchSucceeded = false;
    void tryMarkFlagsArrived() {
      if (flagsFetchSucceeded && segmentStore.allRegisteredSegmentsFetched()) {
        readinessTracker.markSynced('flags', true);
      }
    }

    // --- First flags fetch: 500 — simulated as a failed poll. No onUpdate
    // (nothing parsed), onResult(false). ---
    flagsFetchSucceeded = false;
    tryMarkFlagsArrived();
    expect(readyFired, isFalse);
    expect(segmentsFetchCalls, equals(0));

    // --- Second flags fetch: 200, with a flag referencing a brand-new
    // IN_SEGMENT segment. Mirrors FlagsFetcher.fetchWithOptions: onUpdate
    // (via FlagsSegmentSync) fires, THEN onResult. ---
    processor.processTargetingRules(_splitChanges200WithSegment);
    flagsSegmentSync.onFlagsChanged();
    flagsFetchSucceeded = true;
    tryMarkFlagsArrived();

    // FlagsSegmentSync's immediate fetch is fired unawaited; give the
    // event loop one turn to let it settle (same as production, where
    // readiness is observed asynchronously via whenReady()).
    await Future<void>.delayed(Duration.zero);

    expect(segmentsFetchCalls, equals(1),
        reason: 'the newly-referenced segment MUST be fetched immediately '
            'as part of handling the second flags fetch — there is no '
            'segments timer in this test to fall back on');
    expect(readyFired, isTrue,
        reason: 'READY MUST fire right after the second flags fetch '
            'resolves, once the segment it registered has been fetched — '
            'not stay pending forever waiting for a segments-interval '
            'tick that never happens in this test');
  });

  test(
      'a flags fetch that does not reference any new segment never blocks '
      'on a segments fetch', () async {
    final ruleStore = InMemoryRuleStore();
    final segmentStore = InMemorySegmentStore();
    var segmentsFetchCalls = 0;
    final flagsSegmentSync = FlagsSegmentSync(
      ruleStore: ruleStore,
      segmentStore: segmentStore,
      fetchSegments: () async {
        segmentsFetchCalls++;
        return true;
      },
      logger: SplitLogger(level: LogLevel.none),
    );

    // No flags ever added — nothing referenced, nothing registered.
    flagsSegmentSync.onFlagsChanged();
    await Future<void>.delayed(Duration.zero);

    expect(segmentsFetchCalls, equals(0));
  });
}
