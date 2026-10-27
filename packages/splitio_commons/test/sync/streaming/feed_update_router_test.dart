import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/fetchers/flags_fetcher.dart';
import 'package:splitio_commons/src/sync/streaming/feed_update_router.dart';
import 'package:splitio_commons/src/sync/streaming/flag_update_strategy.dart';
import 'package:splitio_commons/src/sync/streaming/notification_processor.dart';
import 'package:splitio_commons/src/sync/streaming/on_demand_fetch_coordinator.dart';
import 'package:splitio_commons/src/sync/streaming/segment_update_coordinator.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_event.dart';
import 'package:splitio_commons/src/sync/streaming/sync_delay_calculator.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Unit tests for [FeedUpdateRouter.catchUp] (spec §11.3 Fetch effect).
///
/// Server-side has no memberships fetcher (spec §17.2 Axis 3), but it MAY
/// have an `allSegmentsFetcher` seam (reusing `SegmentChangesFetcher.fetch`)
/// so catch-up can refresh every tracked segment after push-up/recovery —
/// otherwise segment stores stay stale while push is up, since
/// `SyncManager.onStreamingUp()` cancels the segments poll timer.
void main() {
  final log = SplitLogger(level: LogLevel.none);

  /// Builds a real [FlagsFetcher] backed by a [MockClient] whose
  /// `/splitChanges` response only resolves once [gate] completes — letting
  /// tests observe ordering relative to the flags fetch's completion, not
  /// just the order statements are invoked in source.
  FlagsFetcher gatedFlagsFetcher(
    Completer<void> gate, {
    required InMemoryRuleStore ruleStore,
    required InMemoryRuleBasedSegmentStore rbsStore,
  }) {
    final mockClient = MockClient((request) async {
      await gate.future;
      return http.Response(
          jsonEncode({
            'ff': {'d': [], 't': 10, 's': 5},
            'rbs': {'d': [], 't': -1, 's': -1},
          }),
          200);
    });
    final httpClient = SplitHttpClient(
        sdkVersion: 'dart_test-1.0.0', apiKey: 'sdk-key', client: mockClient);
    return FlagsFetcher(
      httpClient: httpClient,
      log: log,
      baseUrl: 'https://sdk.example',
      processor: SplitChangeProcessor(
        parser: RuleParser(),
        ruleStore: ruleStore,
        rbsStore: rbsStore,
      ),
      ruleStore: ruleStore,
      rbsStore: rbsStore,
    );
  }

  FeedUpdateRouter buildRouter({
    required FlagsFetcher flagsFetcher,
    Future<bool> Function()? allSegmentsFetcher,
    required InMemoryRuleStore ruleStore,
    Future<bool> Function(String segmentName)? segmentFetcher,
    SegmentUpdateCoordinator? segmentCoordinator,
  }) {
    return FeedUpdateRouter(
      flagsFetcher: flagsFetcher,
      allSegmentsFetcher: allSegmentsFetcher,
      segmentFetcher: segmentFetcher,
      segmentCoordinator: segmentCoordinator,
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      syncDelayCalculator: const SyncDelayCalculator(),
      scheduler: FakeScheduler(),
      matchingKeys: () => const [],
      notificationProcessor: const NotificationProcessor(),
      apply: (StreamingEvent event) async {},
      logger: log,
    );
  }

  test(
      'catch-up on server-side (no memberships) refreshes segments only '
      'after the flags fetch completes, not concurrently', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final flagsGate = Completer<void>();
    var segmentsFetchCount = 0;
    final router = buildRouter(
      flagsFetcher: gatedFlagsFetcher(flagsGate,
          ruleStore: ruleStore, rbsStore: rbsStore),
      allSegmentsFetcher: () {
        segmentsFetchCount++;
        return Future.value(true);
      },
      ruleStore: ruleStore,
    );

    router.catchUp();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(segmentsFetchCount, 0,
        reason: 'segments catch-up MUST NOT run while the flags fetch is '
            'still in flight');

    flagsGate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(segmentsFetchCount, 1,
        reason: 'segments catch-up MUST run once the flags fetch completes');
  });

  test('catch-up swallows a segments-fetch error without throwing', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final flagsGate = Completer<void>()..complete();
    final router = buildRouter(
      flagsFetcher: gatedFlagsFetcher(flagsGate,
          ruleStore: ruleStore, rbsStore: rbsStore),
      allSegmentsFetcher: () => Future<bool>.error('boom'),
      ruleStore: ruleStore,
    );

    expect(() => router.catchUp(), returnsNormally);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    // No uncaught async error should have escaped; reaching this point is
    // the assertion.
  });

  test(
      'catch-up with no allSegmentsFetcher wired (client-side) only fetches '
      'flags — no segments seam invoked', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final flagsGate = Completer<void>()..complete();
    final router = buildRouter(
      flagsFetcher: gatedFlagsFetcher(flagsGate,
          ruleStore: ruleStore, rbsStore: rbsStore),
      ruleStore: ruleStore,
    );

    expect(() => router.catchUp(), returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });

  test(
      'SEGMENT_UPDATE with an int changeNumber and segmentCoordinator wired '
      '→ routed to the coordinator, segmentFetcher NOT called (spec §10.2)',
      () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final flagsGate = Completer<void>()..complete();
    var directFetchCount = 0;
    var coordinatorCalls = 0;
    final segmentCoordinator = SegmentUpdateCoordinator(
      fetcher: (name, {bool noCache = false, int? till}) async {
        coordinatorCalls++;
        return true;
      },
      cursor: (name) => -1,
      scheduler: FakeScheduler(),
      logger: log,
    );
    final router = buildRouter(
      flagsFetcher: gatedFlagsFetcher(flagsGate,
          ruleStore: ruleStore, rbsStore: rbsStore),
      ruleStore: ruleStore,
      segmentFetcher: (name) async {
        directFetchCount++;
        return true;
      },
      segmentCoordinator: segmentCoordinator,
    );

    router.route(const FeedUpdate(type: 'SEGMENT_UPDATE', payload: {
      'type': 'SEGMENT_UPDATE',
      'segmentName': 'seg_a',
      'changeNumber': 100,
    }));
    await Future<void>.delayed(Duration.zero);

    expect(coordinatorCalls, 1);
    expect(directFetchCount, 0,
        reason: 'the coordinator path replaces the direct segment fetch');
  });

  test(
      'SEGMENT_UPDATE with no usable int changeNumber falls back to the '
      'direct segmentFetcher even when segmentCoordinator is wired', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final flagsGate = Completer<void>()..complete();
    var directFetchCount = 0;
    var coordinatorCalls = 0;
    final segmentCoordinator = SegmentUpdateCoordinator(
      fetcher: (name, {bool noCache = false, int? till}) async {
        coordinatorCalls++;
        return true;
      },
      cursor: (name) => -1,
      scheduler: FakeScheduler(),
      logger: log,
    );
    final router = buildRouter(
      flagsFetcher: gatedFlagsFetcher(flagsGate,
          ruleStore: ruleStore, rbsStore: rbsStore),
      ruleStore: ruleStore,
      segmentFetcher: (name) async {
        directFetchCount++;
        return true;
      },
      segmentCoordinator: segmentCoordinator,
    );

    router.route(const FeedUpdate(type: 'SEGMENT_UPDATE', payload: {
      'type': 'SEGMENT_UPDATE',
      'segmentName': 'seg_a',
      // no changeNumber
    }));
    await Future<void>.delayed(Duration.zero);

    expect(coordinatorCalls, 0);
    expect(directFetchCount, 1);
  });

  test(
      'dispose() cancels the flag handler\'s coordinators and the segment '
      'coordinator\'s pending timers', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final scheduler = FakeScheduler();
    final flagsGate = Completer<void>()..complete();
    final ffCoordinator = OnDemandFetchCoordinator(
      cursor: () => -1,
      fetch: ({bool noCache = false, int? till}) async => true,
      scheduler: scheduler,
      logger: log,
      name: 'ff',
    );
    final segmentCoordinator = SegmentUpdateCoordinator(
      fetcher: (name, {bool noCache = false, int? till}) async => true,
      cursor: (name) => -1,
      scheduler: scheduler,
      logger: log,
    );
    final router = FeedUpdateRouter(
      flagsFetcher: gatedFlagsFetcher(flagsGate,
          ruleStore: ruleStore, rbsStore: rbsStore),
      segmentCoordinator: segmentCoordinator,
      ffCoordinator: ffCoordinator,
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      syncDelayCalculator: const SyncDelayCalculator(),
      scheduler: scheduler,
      matchingKeys: () => const [],
      notificationProcessor: const NotificationProcessor(),
      apply: (StreamingEvent event) async {},
      logger: log,
    );

    router.route(const FeedUpdate(type: 'SPLIT_UPDATE', payload: {
      'type': 'SPLIT_UPDATE',
      'changeNumber': 100,
      'pcn': -1,
      'c': 2,
      'd': '',
    }));
    router.route(const FeedUpdate(type: 'SEGMENT_UPDATE', payload: {
      'type': 'SEGMENT_UPDATE',
      'segmentName': 'seg_a',
      'changeNumber': 200,
    }));
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.pendingCount, 2);

    router.dispose();

    expect(scheduler.pendingCount, 0);
  });
}
