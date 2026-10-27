import 'package:splitio_commons/src/auth/auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/http_client/http_client_testing.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/polling/polling_manager_cs.dart';
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

({SyncManager sync, PollingManagerCS polling}) _createSyncManager({
  required SplitHttpClient httpClient,
  StreamingManager? streamingManager,
}) {
  final logger = SplitLogger(level: LogLevel.none);
  final polling = PollingManagerCS(
    bootstrapKey: 'user1',
    flagsFetcher: FlagsFetcher(
      httpClient: httpClient,
      log: logger,
      baseUrl: 'https://sdk.split.io/api',
      processor: SplitChangeProcessor(
        parser: RuleParser(),
        ruleStore: InMemoryRuleStore(),
        rbsStore: InMemoryRuleBasedSegmentStore(),
      ),
      ruleStore: InMemoryRuleStore(),
      rbsStore: InMemoryRuleBasedSegmentStore(),
    ),
    membershipsFetcher: MembershipsFetcher(
      httpClient: httpClient,
      log: logger,
      baseUrl: 'https://sdk.split.io/api',
      processor:
          MembershipsProcessor(membershipStore: InMemoryMembershipStore()),
    ),
    featuresRefreshRate: Duration(
        seconds: const SyncConfig().normalized().featureFlagsPollingRate),
    membershipsRefreshRate:
        Duration(seconds: const SyncConfig().normalized().segmentsPollingRate),
    logger: logger,
  );
  return (
    sync: SyncManager(
      polling: polling,
      logger: logger,
      streamingManager: streamingManager,
    ),
    polling: polling,
  );
}

void main() {
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
        rbsStore: rbsStore,
        membershipStore: membershipStore,
        streamingBaseUri: Uri.parse('https://streaming.example'),
        logger: logger,
        onPushEnabled: onPushEnabled,
        onPushDisabled: onPushDisabled,
      );
    }

    setUp(() {
      // keepOpen: true — every retryable failure (including the stream
      // naturally ending with no lines) now unconditionally drops
      // connectionDown (§11.3). These tests assert the streaming connection
      // STAYS up, so the fake transport must not let the empty default
      // stream end on its own and flip push back down.
      transport = FakeStreamingTransport(statusCode: 200, keepOpen: true);
      httpClient = SplitHttpClient(
          sdkVersion: 'dart_test-1.0.0',
          apiKey: 'test-key',
          client: MockClient((r) async => http.Response('{}', 200)));
    });

    tearDown(() => httpClient.close());

    test('no StreamingManager: startStreaming falls back to startPolling',
        () async {
      final (sync: syncManager, polling: polling) =
          _createSyncManager(httpClient: httpClient);

      await syncManager.startStreaming();

      expect(syncManager.isPolling, isTrue);
      expect(polling.activePollTimerCount, equals(1));

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
      final (sync: syncManager, polling: polling) = _createSyncManager(
        httpClient: httpClient,
        streamingManager: streaming,
      );

      await syncManager.startStreaming();
      await Future<void>.delayed(Duration.zero);

      expect(transport.connectCount, equals(1));
      expect(syncManager.isPolling, isFalse);
      expect(polling.activePollTimerCount, equals(0));

      syncManager.stop();
    });

    test('onStreamingUp stops poll timers', () async {
      final (sync: syncManager, polling: polling) =
          _createSyncManager(httpClient: httpClient);
      syncManager.startPolling();
      expect(polling.activePollTimerCount, greaterThan(0));

      syncManager.onStreamingUp();

      expect(syncManager.isPolling, isFalse);
      expect(polling.activePollTimerCount, equals(0));

      syncManager.stop();
    });

    test('onStreamingUp keeps the streaming connection alive', () async {
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();
      final streaming = buildStreamingManager(
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );
      final (sync: syncManager, polling: polling) = _createSyncManager(
        httpClient: httpClient,
        streamingManager: streaming,
      );

      await syncManager.startStreaming();
      await Future<void>.delayed(Duration.zero);
      expect(streaming.isPushUp, isTrue);

      syncManager.onStreamingUp();

      // Streaming connection stays up; only poll timers are stopped (§8.4).
      expect(streaming.isPushUp, isTrue);
      expect(syncManager.isPolling, isFalse);
      expect(polling.activePollTimerCount, equals(0));

      syncManager.stop();
    });

    test('onStreamingDown (re)starts polling without duplicating timers',
        () async {
      final (sync: syncManager, polling: polling) =
          _createSyncManager(httpClient: httpClient);

      syncManager.onStreamingDown();
      final afterFirst = polling.activePollTimerCount;
      syncManager.onStreamingDown();
      final afterSecond = polling.activePollTimerCount;

      expect(syncManager.isPolling, isTrue);
      expect(afterFirst, equals(1));
      expect(afterSecond, equals(afterFirst));

      syncManager.stop();
    });

    test('up→down→up cycle leaves consistent state (no timer leaks)', () async {
      final (sync: syncManager, polling: polling) =
          _createSyncManager(httpClient: httpClient);

      syncManager.startPolling();
      syncManager.onStreamingUp();
      expect(polling.activePollTimerCount, equals(0));

      syncManager.onStreamingDown();
      expect(polling.activePollTimerCount, equals(1));

      syncManager.onStreamingUp();
      expect(polling.activePollTimerCount, equals(0));

      syncManager.stop();
    });

    test('stop cancels poll timers AND stops streaming; idempotent', () async {
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();
      final streaming = buildStreamingManager(
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );
      final (sync: syncManager, polling: polling) = _createSyncManager(
        httpClient: httpClient,
        streamingManager: streaming,
      );

      await syncManager.startStreaming();
      await Future<void>.delayed(Duration.zero);
      expect(streaming.isPushUp, isTrue);

      syncManager.startPolling();
      syncManager.stop();
      await Future<void>.delayed(Duration.zero);

      expect(polling.activePollTimerCount, equals(0));
      expect(streaming.isPushUp, isFalse);

      // Second stop is safe.
      expect(() => syncManager.stop(), returnsNormally);
    });

    // Regression: stopping a streaming connection that was UP emits
    // NotifyPushDisabled (push went down) in the SAME reduce pass as
    // CloseCurrentSocket, so onStreamingDown() runs synchronously inside
    // `await streamingManager.stop()`. Without a stopped-guard, that
    // onStreamingDown() call restarts the poll timers that stop() just
    // cancelled, and they survive stop() returning.
    test(
        'stop() guards against a push-down callback restarting poll timers '
        'mid-teardown', () async {
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();
      final streaming = buildStreamingManager(
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );
      final (sync: syncManager, polling: polling) = _createSyncManager(
        httpClient: httpClient,
        streamingManager: streaming,
      );

      await syncManager.startStreaming();
      await Future<void>.delayed(Duration.zero);
      expect(streaming.isPushUp, isTrue);
      expect(polling.activePollTimerCount, equals(0));

      await syncManager.stop();

      expect(streaming.isPushUp, isFalse);
      expect(polling.activePollTimerCount, equals(0),
          reason: 'stop() MUST NOT leave a restarted poll timer running: '
              'stopping an up streaming connection triggers a push-down '
              'callback (onStreamingDown) that MUST be a no-op once stop() '
              'has started');
    });

    test('stopStreaming stops the injected streaming manager', () async {
      final ruleStore = InMemoryRuleStore();
      final membershipStore = InMemoryMembershipStore();
      final streaming = buildStreamingManager(
        ruleStore: ruleStore,
        membershipStore: membershipStore,
      );
      final (sync: syncManager, polling: polling) = _createSyncManager(
        httpClient: httpClient,
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
