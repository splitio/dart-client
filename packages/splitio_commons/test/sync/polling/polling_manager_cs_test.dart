import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/polling/polling_manager_cs.dart';
import 'package:splitio_commons/src/sync/sync.dart';
import 'package:test/test.dart';

const _validSplitChangesResponse = '''
{
  "ff": {
    "t": 100,
    "s": -1,
    "d": [
      {
        "name": "my_flag",
        "trafficTypeName": "user",
        "killed": false,
        "defaultTreatment": "off",
        "conditions": [],
        "trafficAllocation": 100,
        "seed": 12345,
        "algo": 2,
        "changeNumber": 100,
        "status": "ACTIVE"
      }
    ]
  },
  "rbs": {
    "t": -1,
    "s": -1,
    "d": []
  }
}
''';

const _validMembershipsResponse = '''
{
  "ms": {
    "k": ["segment_a", "segment_b"],
    "cn": 50
  }
}
''';

PollingManagerCS _createPollingManager({
  required SplitHttpClient httpClient,
  SyncConfig? config,
  InMemoryRuleStore? ruleStore,
  InMemoryRuleBasedSegmentStore? rbsStore,
  InMemoryMembershipStore? membershipStore,
  void Function(List<String>)? onUpdate,
  String bootstrapKey = 'user1',
}) {
  final effectiveRuleStore = ruleStore ?? InMemoryRuleStore();
  final effectiveRbsStore = rbsStore ?? InMemoryRuleBasedSegmentStore();
  final effectiveMembershipStore = membershipStore ?? InMemoryMembershipStore();
  final logger = SplitLogger(level: LogLevel.none);
  const baseUrl = 'https://sdk.split.io/api';
  final syncConfig = config ?? const SyncConfig().normalized();

  final flagsFetcher = FlagsFetcher(
    httpClient: httpClient,
    log: logger,
    baseUrl: baseUrl,
    processor: SplitChangeProcessor(
      parser: RuleParser(),
      ruleStore: effectiveRuleStore,
      rbsStore: effectiveRbsStore,
    ),
    ruleStore: effectiveRuleStore,
    rbsStore: effectiveRbsStore,
    onUpdate: onUpdate,
  );
  final membershipsFetcher = MembershipsFetcher(
    httpClient: httpClient,
    log: logger,
    baseUrl: baseUrl,
    processor: MembershipsProcessor(membershipStore: effectiveMembershipStore),
  );

  return PollingManagerCS(
    bootstrapKey: bootstrapKey,
    flagsFetcher: flagsFetcher,
    membershipsFetcher: membershipsFetcher,
    featuresRefreshRate: Duration(seconds: syncConfig.featureFlagsPollingRate),
    membershipsRefreshRate: Duration(seconds: syncConfig.segmentsPollingRate),
    logger: logger,
  );
}

void main() {
  group('PollingManagerCS', () {
    test('syncAll fetches rules and memberships then returns true', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();

      final polling = _createPollingManager(
        httpClient: httpClient,
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );

      final result = await polling.syncAll();

      expect(result, isTrue);
      expect(ruleStore.get('my_flag'), isNotNull);
      expect(ruleStore.changeNumber(), equals(100));
      expect(membershipStore.isInSegment('segment_a', 'user1'), isTrue);
      expect(membershipStore.isInSegment('segment_b', 'user1'), isTrue);
      expect(membershipStore.isInSegment('segment_c', 'user1'), isFalse);

      polling.stop();
      httpClient.close();
    });

    test('syncAll returns false when rules fetch fails', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response('Internal Server Error', 500);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(httpClient: httpClient);

      final result = await polling.syncAll();
      expect(result, isFalse);

      polling.stop();
      httpClient.close();
    });

    test('syncAll returns false when memberships fetch fails', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(httpClient: httpClient);

      final result = await polling.syncAll();
      expect(result, isFalse);

      polling.stop();
      httpClient.close();
    });

    test('syncAll returns false when both fetches fail', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(httpClient: httpClient);

      final result = await polling.syncAll();
      expect(result, isFalse);

      polling.stop();
      httpClient.close();
    });

    test('syncAll fetches rules and memberships in parallel', () async {
      final requestTimestamps = <String, DateTime>{};

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          requestTimestamps['rules'] = DateTime.now();
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          requestTimestamps['memberships'] = DateTime.now();
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(httpClient: httpClient);

      final result = await polling.syncAll();

      expect(result, isTrue);
      expect(requestTimestamps['rules'], isNotNull);
      expect(requestTimestamps['memberships'], isNotNull);

      final diff = requestTimestamps['memberships']!
          .difference(requestTimestamps['rules']!)
          .inMilliseconds
          .abs();
      expect(diff, lessThan(30),
          reason: 'Both fetches should start nearly simultaneously');

      polling.stop();
      httpClient.close();
    });

    test('syncAll returns true on 304 Not Modified', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response('', 304);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(httpClient: httpClient);

      final result = await polling.syncAll();
      expect(result, isTrue);

      polling.stop();
      httpClient.close();
    });

    test('start does not throw', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(httpClient: httpClient);

      await polling.syncAll();

      // start should not throw
      expect(() => polling.start(), returnsNormally);

      // stop cancels timers without error
      polling.stop();
      httpClient.close();
    });

    test('stop cancels polling timers', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(httpClient: httpClient);

      await polling.syncAll();
      polling.start();

      // Calling stop multiple times should not throw
      polling.stop();
      polling.stop();

      httpClient.close();
    });

    test('onUpdate callback is invoked when flags change', () async {
      final changedFlagsList = <List<String>>[];

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(
        httpClient: httpClient,
        onUpdate: (flags) => changedFlagsList.add(flags),
      );

      await polling.syncAll();

      expect(changedFlagsList, hasLength(1));
      expect(changedFlagsList.first, contains('my_flag'));

      polling.stop();
      httpClient.close();
    });

    test('syncAll sends correct query parameters', () async {
      Uri? capturedUri;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          capturedUri = request.url;
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(httpClient: httpClient);

      await polling.syncAll();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters['since'], equals('-1'));
      expect(capturedUri!.queryParameters['rbSince'], equals('-1'));
      expect(capturedUri!.queryParameters['s'], equals('1.3'));

      polling.stop();
      httpClient.close();
    });

    test('syncAll fetches memberships at correct URL', () async {
      String? membershipsPath;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          membershipsPath = request.url.path;
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(
          httpClient: httpClient, bootstrapKey: 'test_user');

      await polling.syncAll();

      expect(membershipsPath, equals('/api/memberships/test_user'));

      polling.stop();
      httpClient.close();
    });

    test('start twice does not leak the rules timer', () async {
      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: MockClient((r) async => http.Response('{}', 200)));
      final polling = _createPollingManager(httpClient: httpClient);

      polling.start();
      final afterFirst = polling.activePollTimerCount;
      polling.start();
      final afterSecond = polling.activePollTimerCount;

      // No leaked rules timer: count is stable across repeated start.
      expect(afterFirst, equals(1)); // rules timer only (no bound keys)
      expect(afterSecond, equals(afterFirst));

      polling.stop();
      httpClient.close();
    });

    // Regression (§11.3): a timer *count* that stays at 1 is not enough to
    // prove idempotency — the old implementation also kept the count at 1
    // because it cancelled-then-recreated the SAME single rules timer on
    // every call, which resets its remaining time to a full period. If
    // start() is invoked faster than the poll period (e.g. once per
    // retryable streaming failure during exponential backoff while
    // streaming never comes up), that reset starves the timer forever and
    // it never fires. This test proves the timer created on the FIRST call
    // survives untouched across repeated calls by observing an actual fetch
    // land. Bypasses the 30s production floor (enforced by
    // SplitClientConfig, not SyncManager) with a 1s rate so this is fast.
    test(
        'start repeated calls do not reset the rules timer, '
        'so it still fires (regression)', () async {
      int splitChangesCalls = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          splitChangesCalls++;
        }
        return http.Response(_validSplitChangesResponse, 200);
      });
      final httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: mockClient);
      final polling = _createPollingManager(
        httpClient: httpClient,
        config: const SyncConfig(
          featureFlagsPollingRate: 1,
          segmentsPollingRate: 9999,
        ),
      );

      // Simulate repeated onStreamingDown()-driven start() calls
      // 200ms apart (faster than the 1s rules period) for ~1s.
      for (var i = 0; i < 6; i++) {
        polling.start();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      expect(splitChangesCalls, greaterThan(0),
          reason: 'The rules timer created on the first start() call '
              'MUST survive the later no-op calls and fire at its original '
              '1s period, not be reset back to a full period on every call');

      polling.stop();
      httpClient.close();
    });
  });
}
