import 'package:splitio_commons/src/auth/auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/http_client/http_client_testing.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/sync.dart';
import 'package:test/test.dart';

/// Minimal AuthProvider returning a fixed credential (streaming injection tests).
class _FakeAuthProvider implements AuthProvider {
  final Credential _credential;
  _FakeAuthProvider(this._credential);

  @override
  Future<Credential> credential(Target? target) async => _credential;

  @override
  void invalidate(Target? target) {}

  @override
  void clearAll() {}
}

JwtCredential _pushCredential() => const JwtCredential(
      token: 'tok-123',
      channels: ['ch1'],
      pushEnabled: true,
      expiresAt: 9999999999,
      connDelaySeconds: 0,
    );

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

SyncManager _createSyncManager({
  required SplitHttpClient httpClient,
  SyncConfig? config,
  InMemoryRuleStore? ruleStore,
  InMemoryRuleBasedSegmentStore? rbsStore,
  InMemoryMembershipStore? membershipStore,
  void Function(List<String>)? onUpdate,
  StreamingManager? streamingManager,
}) {
  final effectiveRuleStore = ruleStore ?? InMemoryRuleStore();
  final effectiveRbsStore = rbsStore ?? InMemoryRuleBasedSegmentStore();
  final effectiveMembershipStore = membershipStore ?? InMemoryMembershipStore();
  final logger = SplitLogger(level: LogLevel.none);
  const baseUrl = 'https://sdk.split.io/api';

  final ruleParser = RuleParser();
  final processor = SplitChangeProcessor(
    parser: ruleParser,
    ruleStore: effectiveRuleStore,
    rbsStore: effectiveRbsStore,
  );
  final membershipsProcessor = MembershipsProcessor(
    membershipStore: effectiveMembershipStore,
  );

  final flagsFetcher = FlagsFetcher(
    httpClient: httpClient,
    log: logger,
    baseUrl: baseUrl,
    processor: processor,
    ruleStore: effectiveRuleStore,
    rbsStore: effectiveRbsStore,
    onUpdate: onUpdate,
  );
  final membershipsFetcher = MembershipsFetcher(
    httpClient: httpClient,
    log: logger,
    baseUrl: baseUrl,
    processor: membershipsProcessor,
  );

  return SyncManager(
    httpClient: httpClient,
    ruleStore: effectiveRuleStore,
    rbsStore: effectiveRbsStore,
    membershipStore: effectiveMembershipStore,
    config: config ?? const SyncConfig().normalized(),
    baseUrl: baseUrl,
    logger: logger,
    flagsFetcher: flagsFetcher,
    membershipsFetcher: membershipsFetcher,
    streamingManager: streamingManager,
  );
}

void main() {
  group('SyncManager', () {
    test('initialSync fetches rules and memberships then returns true',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();

      final syncManager = _createSyncManager(
        httpClient: httpClient,
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );

      final result = await syncManager.initialSync('user1');

      expect(result, isTrue);
      expect(ruleStore.get('my_flag'), isNotNull);
      expect(ruleStore.changeNumber(), equals(100));
      expect(membershipStore.isInSegment('segment_a', 'user1'), isTrue);
      expect(membershipStore.isInSegment('segment_b', 'user1'), isTrue);
      expect(membershipStore.isInSegment('segment_c', 'user1'), isFalse);

      syncManager.stop();
      httpClient.close();
    });

    test('initialSync returns false when rules fetch fails', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response('Internal Server Error', 500);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      final result = await syncManager.initialSync('user1');
      expect(result, isFalse);

      syncManager.stop();
      httpClient.close();
    });

    test('initialSync returns false when memberships fetch fails', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      final result = await syncManager.initialSync('user1');
      expect(result, isFalse);

      syncManager.stop();
      httpClient.close();
    });

    test('initialSync returns false when both fetches fail', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      final result = await syncManager.initialSync('user1');
      expect(result, isFalse);

      syncManager.stop();
      httpClient.close();
    });

    test('initialSync fetches rules and memberships in parallel', () async {
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

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      final result = await syncManager.initialSync('user1');

      expect(result, isTrue);
      expect(requestTimestamps['rules'], isNotNull);
      expect(requestTimestamps['memberships'], isNotNull);

      final diff = requestTimestamps['memberships']!
          .difference(requestTimestamps['rules']!)
          .inMilliseconds
          .abs();
      expect(diff, lessThan(30),
          reason: 'Both fetches should start nearly simultaneously');

      syncManager.stop();
      httpClient.close();
    });

    test('initialSync returns true on 304 Not Modified', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response('', 304);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      final result = await syncManager.initialSync('user1');
      expect(result, isTrue);

      syncManager.stop();
      httpClient.close();
    });

    test('startPolling does not throw', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splitChanges')) {
          return http.Response(_validSplitChangesResponse, 200);
        }
        if (request.url.path.contains('/memberships/')) {
          return http.Response(_validMembershipsResponse, 200);
        }
        return http.Response('Not Found', 404);
      });

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      await syncManager.initialSync('user1');

      // startPolling should not throw
      expect(() => syncManager.startPolling(), returnsNormally);

      // stop cancels timers without error
      syncManager.stop();
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

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      await syncManager.initialSync('user1');
      syncManager.startPolling();

      // Calling stop multiple times should not throw
      syncManager.stop();
      syncManager.stop();

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

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(
        httpClient: httpClient,
        onUpdate: (flags) => changedFlagsList.add(flags),
      );

      await syncManager.initialSync('user1');

      expect(changedFlagsList, hasLength(1));
      expect(changedFlagsList.first, contains('my_flag'));

      syncManager.stop();
      httpClient.close();
    });

    test('initialSync sends correct query parameters', () async {
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

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      await syncManager.initialSync('user1');

      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters['since'], equals('-1'));
      expect(capturedUri!.queryParameters['rbSince'], equals('-1'));
      expect(capturedUri!.queryParameters['s'], equals('1.3'));

      syncManager.stop();
      httpClient.close();
    });

    test('initialSync fetches memberships at correct URL', () async {
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

      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final syncManager = _createSyncManager(httpClient: httpClient);

      await syncManager.initialSync('test_user');

      expect(membershipsPath, equals('/api/memberships/test_user'));

      syncManager.stop();
      httpClient.close();
    });

    test('startPolling twice does not leak the rules timer', () async {
      final httpClient = SplitHttpClient(
          apiKey: 'test-key',
          client: MockClient((r) async => http.Response('{}', 200)));
      final syncManager = _createSyncManager(httpClient: httpClient);

      syncManager.startPolling();
      final afterFirst = syncManager.activePollTimerCount;
      syncManager.startPolling();
      final afterSecond = syncManager.activePollTimerCount;

      // No leaked rules timer: count is stable across repeated startPolling.
      expect(afterFirst, equals(1)); // rules timer only (no bound keys)
      expect(afterSecond, equals(afterFirst));

      syncManager.stop();
      httpClient.close();
    });
  });

  group('SyncManager sync-mode switch', () {
    late FakeStreamingTransport transport;
    late SplitHttpClient httpClient;

    StreamingManager buildStreamingManager({
      required InMemoryRuleStore ruleStore,
      required InMemoryMembershipStore membershipStore,
      Credential? credential,
      void Function()? onPushEnabled,
      void Function()? onPushDisabled,
    }) {
      final logger = SplitLogger(level: LogLevel.none);
      const baseUrl = 'https://sdk.split.io/api';
      final rbsStore = InMemoryRuleBasedSegmentStore();
      final flagsFetcher = FlagsFetcher(
        httpClient: httpClient,
        log: logger,
        baseUrl: baseUrl,
        processor: SplitChangeProcessor(
          parser: RuleParser(),
          ruleStore: ruleStore,
          rbsStore: rbsStore,
        ),
        ruleStore: ruleStore,
        rbsStore: rbsStore,
      );
      final membershipsFetcher = MembershipsFetcher(
        httpClient: httpClient,
        log: logger,
        baseUrl: baseUrl,
        processor: MembershipsProcessor(membershipStore: membershipStore),
      );
      return StreamingManager(
        transport: transport,
        authProvider: _FakeAuthProvider(credential ?? _pushCredential()),
        flagsFetcher: flagsFetcher,
        membershipsFetcher: membershipsFetcher,
        ruleStore: ruleStore,
        membershipStore: membershipStore,
        streamingBaseUri: Uri.parse('https://streaming.example'),
        logger: logger,
        onPushEnabled: onPushEnabled,
        onPushDisabled: onPushDisabled,
      );
    }

    setUp(() {
      transport = FakeStreamingTransport(statusCode: 200);
      httpClient = SplitHttpClient(
          apiKey: 'test-key',
          client: MockClient((r) async => http.Response('{}', 200)));
    });

    tearDown(() => httpClient.close());

    test('no StreamingManager: startStreaming falls back to startPolling',
        () async {
      final syncManager = _createSyncManager(httpClient: httpClient);

      await syncManager.startStreaming();

      expect(syncManager.isPolling, isTrue);
      expect(syncManager.activePollTimerCount, equals(1));

      syncManager.stop();
    });

    test(
        'with StreamingManager: startStreaming starts streaming, no poll timers',
        () async {
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();
      final streaming = buildStreamingManager(
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );
      final syncManager = _createSyncManager(
        httpClient: httpClient,
        ruleStore: ruleStore,
        membershipStore: membershipStore,
        streamingManager: streaming,
      );

      await syncManager.startStreaming();
      await Future<void>.delayed(Duration.zero);

      expect(transport.connectCount, equals(1));
      expect(syncManager.isPolling, isFalse);
      expect(syncManager.activePollTimerCount, equals(0));

      syncManager.stop();
    });

    test('onStreamingUp stops poll timers', () async {
      final syncManager = _createSyncManager(httpClient: httpClient);
      syncManager.startPolling();
      expect(syncManager.activePollTimerCount, greaterThan(0));

      syncManager.onStreamingUp();

      expect(syncManager.isPolling, isFalse);
      expect(syncManager.activePollTimerCount, equals(0));

      syncManager.stop();
    });

    test('onStreamingUp keeps the streaming connection alive', () async {
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();
      final streaming = buildStreamingManager(
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );
      final syncManager = _createSyncManager(
        httpClient: httpClient,
        ruleStore: ruleStore,
        membershipStore: membershipStore,
        streamingManager: streaming,
      );

      await syncManager.startStreaming();
      await Future<void>.delayed(Duration.zero);
      expect(streaming.isPushUp, isTrue);

      syncManager.onStreamingUp();

      // Streaming connection stays up; only poll timers are stopped (§8.4).
      expect(streaming.isPushUp, isTrue);
      expect(syncManager.isPolling, isFalse);
      expect(syncManager.activePollTimerCount, equals(0));

      syncManager.stop();
    });

    test('onStreamingDown (re)starts polling without duplicating timers',
        () async {
      final syncManager = _createSyncManager(httpClient: httpClient);

      syncManager.onStreamingDown();
      final afterFirst = syncManager.activePollTimerCount;
      syncManager.onStreamingDown();
      final afterSecond = syncManager.activePollTimerCount;

      expect(syncManager.isPolling, isTrue);
      expect(afterFirst, equals(1));
      expect(afterSecond, equals(afterFirst));

      syncManager.stop();
    });

    test('up→down→up cycle leaves consistent state (no timer leaks)', () async {
      final syncManager = _createSyncManager(httpClient: httpClient);

      syncManager.startPolling();
      syncManager.onStreamingUp();
      expect(syncManager.activePollTimerCount, equals(0));

      syncManager.onStreamingDown();
      expect(syncManager.activePollTimerCount, equals(1));

      syncManager.onStreamingUp();
      expect(syncManager.activePollTimerCount, equals(0));

      syncManager.stop();
    });

    test('stop cancels poll timers AND stops streaming; idempotent', () async {
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();
      final streaming = buildStreamingManager(
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );
      final syncManager = _createSyncManager(
        httpClient: httpClient,
        ruleStore: ruleStore,
        membershipStore: membershipStore,
        streamingManager: streaming,
      );

      await syncManager.startStreaming();
      await Future<void>.delayed(Duration.zero);
      expect(streaming.isPushUp, isTrue);

      syncManager.startPolling();
      syncManager.stop();
      await Future<void>.delayed(Duration.zero);

      expect(syncManager.activePollTimerCount, equals(0));
      expect(streaming.isPushUp, isFalse);

      // Second stop is safe.
      expect(() => syncManager.stop(), returnsNormally);
    });

    test('stopStreaming stops the injected streaming manager', () async {
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();
      final streaming = buildStreamingManager(
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );
      final syncManager = _createSyncManager(
        httpClient: httpClient,
        ruleStore: ruleStore,
        membershipStore: membershipStore,
        streamingManager: streaming,
      );

      await syncManager.startStreaming();
      await Future<void>.delayed(Duration.zero);
      expect(streaming.isPushUp, isTrue);

      await syncManager.stopStreaming();
      expect(streaming.isPushUp, isFalse);

      syncManager.stop();
    });
  });
}
