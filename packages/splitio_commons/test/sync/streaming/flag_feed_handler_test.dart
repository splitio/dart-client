import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/fetchers/flags_fetcher.dart';
import 'package:splitio_commons/src/sync/streaming/flag_feed_handler.dart';
import 'package:splitio_commons/src/sync/streaming/flag_update_strategy.dart';
import 'package:splitio_commons/src/sync/streaming/notification_processor.dart';
import 'package:splitio_commons/src/sync/streaming/on_demand_fetch_coordinator.dart';
import 'package:test/test.dart';

import '../compression/inflate_vectors.dart';

import 'fakes.dart';

/// Unit tests for [FlagFeedHandler] — the collaborator extracted out of
/// [FeedUpdateRouter] (Tidy First split) that now also owns the post-apply
/// side effect spec §12.1 requires: after an in-place `SPLIT_UPDATE` apply,
/// a segment it just registered must actually be fetched (server-side), not
/// left stale until an unrelated catch-up/reconnect.
void main() {
  final log = SplitLogger(level: LogLevel.none);

  /// Encodes a minimal flag definition to the base64(utf8(JSON)) form used
  /// in a `SPLIT_UPDATE` `d` field (uncompressed, c == 0).
  String encode(String name, int changeNumber) =>
      base64.encode(utf8.encode(jsonEncode({
        'name': name,
        'trafficTypeName': 'user',
        'killed': false,
        'defaultTreatment': 'off',
        'conditions': [],
        'trafficAllocation': 100,
        'seed': 1,
        'algo': 2,
        'changeNumber': changeNumber,
        'status': 'ACTIVE',
      })));

  FeedUpdate inPlaceSplitUpdate(
          {required int pcn, required int changeNumber}) =>
      FeedUpdate(type: 'SPLIT_UPDATE', payload: {
        'type': 'SPLIT_UPDATE',
        'changeNumber': changeNumber,
        'pcn': pcn,
        'c': 0,
        'd': encode('flag_a', changeNumber),
      });

  FeedUpdate fetchRequiredSplitUpdate(
          {required int pcn, required int changeNumber}) =>
      FeedUpdate(type: 'SPLIT_UPDATE', payload: {
        'type': 'SPLIT_UPDATE',
        'changeNumber': changeNumber,
        'pcn': pcn,
        'c': 2, // compressed → always falls back to fetch
        'd': '',
      });

  /// A real [FlagsFetcher] backed by a [MockClient] that counts invocations
  /// via [onFetch] and always returns a no-op diff.
  FlagsFetcher countingFlagsFetcher(
    void Function() onFetch, {
    required InMemoryRuleStore ruleStore,
    required InMemoryRuleBasedSegmentStore rbsStore,
  }) {
    final mockClient = MockClient((request) async {
      onFetch();
      return http.Response(
          jsonEncode({
            'ff': {'d': [], 't': ruleStore.changeNumber(), 's': 5},
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

  test(
      'SPLIT_UPDATE applied in place → segments refetched, no /splitChanges '
      'fetch', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    var flagsFetchCount = 0;
    var segmentsFetchCount = 0;
    final handler = FlagFeedHandler(
      flagsFetcher: countingFlagsFetcher(() => flagsFetchCount++,
          ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      allSegmentsFetcher: () {
        segmentsFetchCount++;
        return Future.value(true);
      },
      logger: log,
    );

    handler.route(inPlaceSplitUpdate(pcn: -1, changeNumber: 100));
    await Future<void>.delayed(Duration.zero);

    expect(flagsFetchCount, 0,
        reason: 'an in-place apply MUST NOT trigger a /splitChanges fetch');
    expect(segmentsFetchCount, 1,
        reason: 'a newly-registered segment MUST be fetched right after an '
            'in-place apply (spec §12.1), not left stale');
  });

  test(
      'SPLIT_UPDATE fetch required (fallback) → /splitChanges fetched, '
      'segments NOT refetched directly', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    var flagsFetchCount = 0;
    var segmentsFetchCount = 0;
    final handler = FlagFeedHandler(
      flagsFetcher: countingFlagsFetcher(() => flagsFetchCount++,
          ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      allSegmentsFetcher: () {
        segmentsFetchCount++;
        return Future.value(true);
      },
      logger: log,
    );

    handler.route(fetchRequiredSplitUpdate(pcn: -1, changeNumber: 100));
    await Future<void>.delayed(Duration.zero);

    expect(flagsFetchCount, 1,
        reason: 'a fetch-fallback outcome MUST trigger /splitChanges');
    expect(segmentsFetchCount, 0,
        reason: 'the fetched /splitChanges response already carries any '
            'segment registration side effects via its own onUpdate — a '
            'direct segments refetch here would be redundant');
  });

  test(
      'RB_SEGMENT_UPDATE always triggers a full flags fetch (in-place RBS '
      'deferred)', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    var flagsFetchCount = 0;
    var segmentsFetchCount = 0;
    final handler = FlagFeedHandler(
      flagsFetcher: countingFlagsFetcher(() => flagsFetchCount++,
          ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      allSegmentsFetcher: () {
        segmentsFetchCount++;
        return Future.value(true);
      },
      logger: log,
    );

    handler.route(const FeedUpdate(type: 'RB_SEGMENT_UPDATE', payload: {}));
    await Future<void>.delayed(Duration.zero);

    expect(flagsFetchCount, 1);
    expect(segmentsFetchCount, 0);
  });

  test('RB_SEGMENT_UPDATE with a valid gzip payload still fetches (unchanged)',
      () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    var flagsFetchCount = 0;
    final handler = FlagFeedHandler(
      flagsFetcher: countingFlagsFetcher(() => flagsFetchCount++,
          ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      logger: log,
    );

    handler.route(const FeedUpdate(type: 'RB_SEGMENT_UPDATE', payload: {
      'changeNumber': 5,
      'pcn': -1,
      'c': 1,
      'd': jsSplit0C1,
    }));
    await Future<void>.delayed(Duration.zero);

    expect(flagsFetchCount, 1);
    expect(rbsStore.changeNumber(), -1);
  });

  test(
      'in-place apply with no allSegmentsFetcher wired (client-side) does '
      'not throw and performs no segments fetch', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final handler = FlagFeedHandler(
      flagsFetcher:
          countingFlagsFetcher(() {}, ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      logger: log,
    );

    expect(() => handler.route(inPlaceSplitUpdate(pcn: -1, changeNumber: 100)),
        returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });

  test('in-place apply segments-refetch error is swallowed', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final handler = FlagFeedHandler(
      flagsFetcher:
          countingFlagsFetcher(() {}, ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      allSegmentsFetcher: () => Future<bool>.error('boom'),
      logger: log,
    );

    expect(() => handler.route(inPlaceSplitUpdate(pcn: -1, changeNumber: 100)),
        returnsNormally);
    await Future<void>.delayed(Duration.zero);
    // No uncaught async error should have escaped; reaching this point is
    // the assertion.
  });

  test(
      'fetch-required SPLIT_UPDATE with an int changeNumber and ffCoordinator '
      'wired → routed to the coordinator, no direct /splitChanges fetch '
      '(spec §10.2)', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    var flagsFetchCount = 0;
    var coordinatorCalls = 0;
    final ffCoordinator = OnDemandFetchCoordinator(
      cursor: () => -1, // never converges on its own — fine, we just count
      fetch: ({bool noCache = false, int? till}) async {
        coordinatorCalls++;
        return true;
      },
      scheduler: FakeScheduler(),
      logger: log,
    );
    final handler = FlagFeedHandler(
      flagsFetcher: countingFlagsFetcher(() => flagsFetchCount++,
          ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      ffCoordinator: ffCoordinator,
      logger: log,
    );

    handler.route(fetchRequiredSplitUpdate(pcn: -1, changeNumber: 100));
    await Future<void>.delayed(Duration.zero);

    expect(coordinatorCalls, 1);
    expect(flagsFetchCount, 0,
        reason: 'the coordinator path replaces the direct fetch entirely');
  });

  test(
      'fetch-required SPLIT_UPDATE with no usable int changeNumber falls '
      'back to a direct /splitChanges fetch even when ffCoordinator is '
      'wired', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    var flagsFetchCount = 0;
    var coordinatorCalls = 0;
    final ffCoordinator = OnDemandFetchCoordinator(
      cursor: () => -1,
      fetch: ({bool noCache = false, int? till}) async {
        coordinatorCalls++;
        return true;
      },
      scheduler: FakeScheduler(),
      logger: log,
    );
    final handler = FlagFeedHandler(
      flagsFetcher: countingFlagsFetcher(() => flagsFetchCount++,
          ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      ffCoordinator: ffCoordinator,
      logger: log,
    );
    final update = FeedUpdate(type: 'SPLIT_UPDATE', payload: const {
      'type': 'SPLIT_UPDATE',
      'pcn': -1,
      'c': 2,
      'd': '',
      // no changeNumber at all
    });

    handler.route(update);
    await Future<void>.delayed(Duration.zero);

    expect(coordinatorCalls, 0);
    expect(flagsFetchCount, 1);
  });

  test(
      'RB_SEGMENT_UPDATE with an int changeNumber and rbsCoordinator wired → '
      'routed to the coordinator, no full flags fetch', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    var flagsFetchCount = 0;
    var coordinatorCalls = 0;
    final rbsCoordinator = OnDemandFetchCoordinator(
      cursor: () => -1,
      fetch: ({bool noCache = false, int? till}) async {
        coordinatorCalls++;
        return true;
      },
      scheduler: FakeScheduler(),
      logger: log,
    );
    final handler = FlagFeedHandler(
      flagsFetcher: countingFlagsFetcher(() => flagsFetchCount++,
          ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      rbsCoordinator: rbsCoordinator,
      logger: log,
    );

    handler.route(FeedUpdate(type: 'RB_SEGMENT_UPDATE', payload: const {
      'type': 'RB_SEGMENT_UPDATE',
      'changeNumber': 100,
    }));
    await Future<void>.delayed(Duration.zero);

    expect(coordinatorCalls, 1);
    expect(flagsFetchCount, 0);
  });

  test(
      'RB_SEGMENT_UPDATE with no usable int changeNumber falls back to a '
      'full flags fetch even when rbsCoordinator is wired', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    var flagsFetchCount = 0;
    var coordinatorCalls = 0;
    final rbsCoordinator = OnDemandFetchCoordinator(
      cursor: () => -1,
      fetch: ({bool noCache = false, int? till}) async {
        coordinatorCalls++;
        return true;
      },
      scheduler: FakeScheduler(),
      logger: log,
    );
    final handler = FlagFeedHandler(
      flagsFetcher: countingFlagsFetcher(() => flagsFetchCount++,
          ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      rbsCoordinator: rbsCoordinator,
      logger: log,
    );

    handler.route(const FeedUpdate(type: 'RB_SEGMENT_UPDATE', payload: {}));
    await Future<void>.delayed(Duration.zero);

    expect(coordinatorCalls, 0);
    expect(flagsFetchCount, 1);
  });

  test('dispose() cancels both coordinators\' pending retry timers', () async {
    final scheduler = FakeScheduler();
    final ffCoordinator = OnDemandFetchCoordinator(
      cursor: () => -1,
      fetch: ({bool noCache = false, int? till}) async => true,
      scheduler: scheduler,
      logger: log,
      name: 'ff',
    );
    final rbsCoordinator = OnDemandFetchCoordinator(
      cursor: () => -1,
      fetch: ({bool noCache = false, int? till}) async => true,
      scheduler: scheduler,
      logger: log,
      name: 'rbs',
    );
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final handler = FlagFeedHandler(
      flagsFetcher:
          countingFlagsFetcher(() {}, ruleStore: ruleStore, rbsStore: rbsStore),
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      ffCoordinator: ffCoordinator,
      rbsCoordinator: rbsCoordinator,
      logger: log,
    );

    handler.route(fetchRequiredSplitUpdate(pcn: -1, changeNumber: 100));
    handler.route(const FeedUpdate(type: 'RB_SEGMENT_UPDATE', payload: {
      'type': 'RB_SEGMENT_UPDATE',
      'changeNumber': 200,
    }));
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.pendingCount, 2);

    handler.dispose();

    expect(scheduler.pendingCount, 0);
  });

  test('fetchFlags() swallows a flags-fetch error without throwing', () async {
    final ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    final mockClient = MockClient((request) async => http.Response('', 500));
    final httpClient = SplitHttpClient(
        sdkVersion: 'dart_test-1.0.0', apiKey: 'sdk-key', client: mockClient);
    final flagsFetcher = FlagsFetcher(
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
    final handler = FlagFeedHandler(
      flagsFetcher: flagsFetcher,
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore),
      logger: log,
    );

    final result = await handler.fetchFlags();
    expect(result, isFalse);
  });
}
