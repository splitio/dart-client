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
import 'package:splitio_commons/src/sync/streaming/streaming_event.dart';
import 'package:splitio_commons/src/sync/streaming/streaming_fetch_coordinators.dart';
import 'package:splitio_commons/src/sync/streaming/sync_delay_calculator.dart';
import 'package:test/test.dart';

import 'fakes.dart';

Map<String, dynamic> _flag(int cn,
        {bool killed = false, String dt = 'on', String status = 'ACTIVE'}) =>
    {
      'name': 'flag_a',
      'trafficTypeName': 'user',
      'killed': killed,
      'defaultTreatment': dt,
      'conditions': <Map<String, dynamic>>[],
      'trafficAllocation': 100,
      'trafficAllocationSeed': 1,
      'seed': 1,
      'algo': 2,
      'changeNumber': cn,
      'status': status,
      'configurations': <String, dynamic>{},
      'sets': <String>[],
    };

/// Regression: a `/splitChanges` response that was in flight while newer
/// changes landed in place via streaming (SPLIT_UPDATE) must not overwrite
/// the newer definitions or roll the ff cursor back. Otherwise, with polling
/// off while streaming, the store would serve a stale flag indefinitely.
void main() {
  final log = SplitLogger(level: LogLevel.none);
  late InMemoryRuleStore ruleStore;
  late FeedUpdateRouter router;
  late int serverCn;
  late Map<String, dynamic> serverDef;
  Completer<void>? gate;
  final requests = <Uri>[];

  setUp(() async {
    requests.clear();
    ruleStore = InMemoryRuleStore();
    final rbsStore = InMemoryRuleBasedSegmentStore();
    serverCn = 1000;
    serverDef = _flag(1000);
    final client = MockClient((req) async {
      requests.add(req.url);
      // Snapshot the server state at request time, then (optionally) delay
      // the response — simulating CDN latency while newer notifications land.
      final snapCn = serverCn;
      final snapDef = serverDef;
      final g = gate;
      if (g != null) await g.future;
      final serverCn_ = snapCn;
      final since = int.parse(req.url.queryParameters['since']!);
      final behind = since < serverCn_;
      return http.Response(
          jsonEncode({
            'ff': {
              's': since,
              't': behind ? serverCn_ : since,
              'd': behind ? [snapDef] : [],
            },
            'rbs': {'s': -1, 't': -1, 'd': []},
          }),
          200);
    });
    final fetcher = FlagsFetcher(
      httpClient: SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0', apiKey: 'k', client: client),
      log: log,
      baseUrl: 'https://sdk.example',
      processor: SplitChangeProcessor(
          parser: RuleParser(), ruleStore: ruleStore, rbsStore: rbsStore),
      ruleStore: ruleStore,
      rbsStore: rbsStore,
    );
    final scheduler = FakeScheduler();
    final c = buildOnDemandCoordinators(
      ffCursor: ruleStore.changeNumber,
      rbsCursor: rbsStore.changeNumber,
      flagsFetch: fetcher.fetchWithOptions,
      scheduler: scheduler,
      logger: log,
    );
    router = FeedUpdateRouter(
      flagsFetcher: fetcher,
      ffCoordinator: c.ff,
      rbsCoordinator: c.rbs,
      flagStrategy: FlagUpdateStrategy(ruleStore: ruleStore, logger: log),
      syncDelayCalculator: const SyncDelayCalculator(),
      scheduler: scheduler,
      matchingKeys: () => const [],
      notificationProcessor: const NotificationProcessor(),
      apply: (StreamingEvent e) async {},
      logger: log,
    );
    await fetcher.fetch();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('SPLIT_KILL then SPLIT_UPDATE restore converges via fetch', () async {
    serverCn = 1001;
    serverDef = _flag(1001, killed: true, dt: 'off');
    router.route(const FeedUpdate(type: 'SPLIT_KILL', payload: {
      'type': 'SPLIT_KILL',
      'changeNumber': 1001,
      'splitName': 'flag_a',
      'defaultTreatment': 'off',
    }));
    await settle();
    serverCn = 1002;
    serverDef = _flag(1002);
    router.route(const FeedUpdate(type: 'SPLIT_UPDATE', payload: {
      'type': 'SPLIT_UPDATE',
      'changeNumber': 1002,
      'pcn': 1001,
      'c': 0,
      'd': '',
    }));
    await settle();
    expect(ruleStore.get('flag_a')!.killed, isFalse);
  });

  test('in-flight stale fetch does not regress newer in-place updates',
      () async {
    String b64(Map<String, dynamic> m) =>
        base64.encode(utf8.encode(jsonEncode(m)));
    gate = Completer<void>();
    serverCn = 1001;
    serverDef = _flag(1001, killed: true, dt: 'off');
    router.route(const FeedUpdate(type: 'SPLIT_KILL', payload: {
      'type': 'SPLIT_KILL',
      'changeNumber': 1001,
      'splitName': 'flag_a',
      'defaultTreatment': 'off',
    }));
    await settle(); // fetch since=1000 now in flight, snapshot = killed@1001
    router.route(FeedUpdate(type: 'SPLIT_UPDATE', payload: {
      'type': 'SPLIT_UPDATE',
      'changeNumber': 1001,
      'pcn': 1000,
      'c': 0,
      'd': b64(_flag(1001, killed: true, dt: 'off')),
    }));
    serverCn = 1002;
    serverDef = _flag(1002);
    router.route(FeedUpdate(type: 'SPLIT_UPDATE', payload: {
      'type': 'SPLIT_UPDATE',
      'changeNumber': 1002,
      'pcn': 1001,
      'c': 0,
      'd': b64(_flag(1002)),
    }));
    expect(ruleStore.changeNumber(), 1002);
    expect(ruleStore.get('flag_a')!.killed, isFalse);
    gate!.complete(); // stale response (t=1001, killed) lands now
    gate = null;
    await settle();
    expect(ruleStore.changeNumber(), 1002);
    expect(ruleStore.get('flag_a')!.killed, isFalse,
        reason: 'a stale fetch response MUST NOT regress the store');
  });

  test('SPLIT_UPDATE for an archived flag removes it via fetch', () async {
    serverCn = 1001;
    serverDef = _flag(1001, status: 'ARCHIVED');
    router.route(const FeedUpdate(type: 'SPLIT_UPDATE', payload: {
      'type': 'SPLIT_UPDATE',
      'changeNumber': 1001,
      'pcn': 1000,
    }));
    await settle();
    expect(ruleStore.get('flag_a'), isNull);
  });
}
