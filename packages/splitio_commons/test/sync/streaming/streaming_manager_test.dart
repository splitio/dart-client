import 'dart:async';
import 'dart:convert';

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

import '../compression/inflate_vectors.dart';
import 'fakes.dart';

/// AuthProvider stub returning a configurable credential and counting
/// invalidate() calls.
class FakeAuthProvider implements AuthProvider {
  Credential credentialToReturn;
  int invalidateCount = 0;
  int credentialCount = 0;

  FakeAuthProvider(this.credentialToReturn);

  @override
  Future<Credential> credential(Target? target) async {
    credentialCount++;
    return credentialToReturn;
  }

  @override
  void invalidate(Target? target) => invalidateCount++;

  @override
  void clearAll() {}
}

/// AuthProvider whose credential() future is gated on an external completer so
/// tests can hold an auth fetch in flight and fire a concurrent connect/reconnect
/// during the async gap (TOCTOU race coverage, §11.3).
class GatedAuthProvider implements AuthProvider {
  final Credential credentialToReturn;
  final List<Completer<Credential>> _pending = [];
  int credentialCount = 0;
  int invalidateCount = 0;

  GatedAuthProvider(this.credentialToReturn);

  @override
  Future<Credential> credential(Target? target) {
    credentialCount++;
    final c = Completer<Credential>();
    _pending.add(c);
    return c.future;
  }

  /// Completes every gated credential fetch that is currently in flight.
  void releaseAll() {
    final pending = List<Completer<Credential>>.from(_pending);
    _pending.clear();
    for (final c in pending) {
      c.complete(credentialToReturn);
    }
  }

  @override
  void invalidate(Target? target) => invalidateCount++;

  @override
  void clearAll() {}
}

JwtCredential _pushCredential() => const JwtCredential(
      token: 'tok-123',
      channels: ['ch1', 'ch2'],
      pushEnabled: true,
      expiresAt: 9999999999,
      connDelaySeconds: 0,
    );

JwtCredential _pollCredential() => const JwtCredential(
      token: '',
      channels: [],
      pushEnabled: false,
      expiresAt: 9999999999,
      connDelaySeconds: 0,
    );

/// A message event line-set: an Ably envelope whose data is the inner
/// notification JSON string.
List<String> _messageFrame(Map<String, dynamic> inner,
    {String channel = 'ch1'}) {
  final envelope = jsonEncode({
    'channel': channel,
    'data': jsonEncode(inner),
  });
  return ['event: message', 'data: $envelope', ''];
}

void main() {
  late FakeStreamingTransport transport;
  late FakeScheduler scheduler;
  late FakeClock clock;
  late InMemoryRuleStore ruleStore;
  late InMemoryRuleBasedSegmentStore rbsStore;
  late InMemoryMembershipStore membershipStore;
  late int flagsFetchCount;
  late int membershipsFetchCount;
  late FlagsFetcher flagsFetcher;
  late MembershipsFetcher membershipsFetcher;

  final log = SplitLogger(level: LogLevel.none);
  const key = 'user-1';

  void buildFetchers() {
    flagsFetchCount = 0;
    membershipsFetchCount = 0;
    final mockClient = MockClient((request) async {
      final path = request.url.path;
      if (path.contains('splitChanges')) {
        flagsFetchCount++;
        return http.Response(
            jsonEncode({
              'ff': {'d': [], 't': 10, 's': 5},
              'rbs': {'d': [], 't': -1, 's': -1},
            }),
            200);
      }
      if (path.contains('memberships')) {
        membershipsFetchCount++;
        return http.Response(jsonEncode({'ms': {}, 'ls': {}}), 200);
      }
      return http.Response('{}', 200);
    });
    final httpClient = SplitHttpClient(
        sdkVersion: 'dart_test-1.0.0', apiKey: 'sdk-key', client: mockClient);
    flagsFetcher = FlagsFetcher(
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
    membershipsFetcher = MembershipsFetcher(
      httpClient: httpClient,
      log: log,
      baseUrl: 'https://sdk.example',
      processor: MembershipsProcessor(membershipStore: membershipStore),
    );
    membershipsFetcher.bindKey(key);
  }

  setUp(() {
    transport = FakeStreamingTransport();
    scheduler = FakeScheduler();
    clock = FakeClock();
    ruleStore = InMemoryRuleStore();
    rbsStore = InMemoryRuleBasedSegmentStore();
    membershipStore = InMemoryMembershipStore();
    buildFetchers();
  });

  StreamingManager build(
    AuthProvider auth, {
    void Function()? onPushEnabled,
    void Function()? onPushDisabled,
    void Function(SyncMode, SyncModeChangeReason)? onSyncModeChanged,
    List<String> Function()? matchingKeys,
    SplitLogger? logger,
    Future<bool> Function(String)? segmentFetcher,
  }) {
    return StreamingManager(
      transport: transport,
      authProvider: auth,
      flagsFetcher: flagsFetcher,
      membershipsFetcher: membershipsFetcher,
      segmentFetcher: segmentFetcher,
      ruleStore: ruleStore,
      rbsStore: rbsStore,
      membershipStore: membershipStore,
      streamingBaseUri: Uri.parse('https://streaming.example'),
      logger: logger ?? log,
      scheduler: scheduler,
      clock: clock,
      matchingKeys: matchingKeys ?? () => [key],
      onPushEnabled: onPushEnabled,
      onPushDisabled: onPushDisabled,
      onSyncModeChanged: onSyncModeChanged,
    );
  }

  test('start with pushEnabled + 200 → socket opened, push enabled, catch-up',
      () async {
    transport.statusCode = 200;
    transport.lines = [':keepalive']; // no dispatched frames
    // Hold the connection open: every retryable failure (including the
    // stream naturally ending) now drops connectionDown unconditionally
    // (§11.3), so this test — which asserts push STAYS up — must not let
    // the stream end on its own.
    transport.keepOpen = true;
    var pushed = false;
    final mgr = build(FakeAuthProvider(_pushCredential()),
        onPushEnabled: () => pushed = true);

    await mgr.start();
    await Future<void>.delayed(Duration.zero);

    expect(transport.connectCount, 1);
    expect(mgr.isPushUp, isTrue);
    expect(pushed, isTrue);
    // Catch-up Fetch effect on SocketOpened.
    expect(flagsFetchCount, 1);
    expect(membershipsFetchCount, 1);
  });

  test('SSE connect headers do not include Cache-Control (CORS-safe)',
      () async {
    // Cache-Control is applied only to /splitChanges and /memberships fetches
    // (see flags_fetcher/memberships_fetcher tests). The SSE connect MUST NOT
    // carry it, because the browser would trigger a CORS preflight against the
    // streaming endpoint and fail.
    transport.statusCode = 200;
    final mgr = build(FakeAuthProvider(_pushCredential()));
    await mgr.start();
    await Future<void>.delayed(Duration.zero);

    final headers = transport.lastHeaders!;
    expect(headers.containsKey('Cache-Control'), isFalse);
    expect(headers.containsKey('cache-control'), isFalse);
    expect(headers['Accept'], 'text/event-stream');
  });

  test('SSE Uri built from credential + streamingBaseUri', () async {
    transport.statusCode = 200;
    final mgr = build(FakeAuthProvider(_pushCredential()));
    await mgr.start();
    await Future<void>.delayed(Duration.zero);

    final uri = transport.lastUri!;
    expect(uri.path, '/sse');
    expect(uri.queryParameters['channels'], 'ch1,ch2');
    expect(uri.queryParameters['accessToken'], 'tok-123');
    expect(uri.queryParameters['heartbeats'], 'true');
    expect(uri.host, 'streaming.example');
  });

  test('start with pushEnabled=false → no socket, poll fallback fires',
      () async {
    var polled = false;
    final mgr = build(FakeAuthProvider(_pollCredential()),
        onPushDisabled: () => polled = true);

    await mgr.start();

    expect(transport.connectCount, 0);
    expect(polled, isTrue);
    expect(mgr.isPushUp, isFalse);
  });

  test('pushEnabled=true but empty channels → no socket, poll fallback fires',
      () async {
    // A credential with push enabled but zero channels would open a socket that
    // subscribes to nothing ("streaming up but receiving nothing"). The guard in
    // _openSocket treats empty channels as poll-only, exactly like
    // pushEnabled=false, so it MUST fall back to polling without connecting.
    var polled = false;
    final mgr = build(
        FakeAuthProvider(const JwtCredential(
          token: 'tok-123',
          channels: [],
          pushEnabled: true,
          expiresAt: 9999999999,
          connDelaySeconds: 0,
        )),
        onPushDisabled: () => polled = true);

    await mgr.start();

    expect(transport.connectCount, 0,
        reason: 'empty channels must not connect');
    expect(polled, isTrue);
    expect(mgr.isPushUp, isFalse);
  });

  test('connect 401 → InvalidateToken + reconnect scheduled', () async {
    transport.statusCode = 401;
    final auth = FakeAuthProvider(_pushCredential());
    final mgr = build(auth);

    await mgr.start();
    await Future<void>.delayed(Duration.zero);

    expect(auth.invalidateCount, 1);
    expect(scheduler.pendingCount, 1);
  });

  test(
      'after connect, 1st failure immediately drops connectionDown and '
      'notifies poll fallback (§11.3: the old ≥2-consecutive-failures '
      'threshold before connectionDown is removed)', () async {
    // Connect succeeds first (empty stream → onDone → retryable drop = fail 1).
    transport.statusCode = 200;
    var pollCount = 0;
    final mgr = build(FakeAuthProvider(_pushCredential()),
        onPushDisabled: () => pollCount++);

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // The very FIRST retryable failure after a healthy connect already
    // closes the socket, drops the connection axis and notifies poll
    // fallback — no more "needs 2 failures" grace period.
    expect(scheduler.pendingCount, 1);
    expect(mgr.state.connectionDown, isTrue);
    expect(pollCount, 1,
        reason: 'every retryable failure MUST notify poll fallback, '
            'including the first');
  });

  test(
      'a second consecutive failure keeps connectionDown down and notifies '
      'poll fallback again (receivers MUST treat it idempotently, §11.3)',
      () async {
    // Healthy connect first, then failing reconnects.
    transport.statusCode = 200;
    var pollCount = 0;
    final mgr = build(FakeAuthProvider(_pushCredential()),
        onPushDisabled: () => pollCount++);

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(pollCount, 1, reason: 'already dropped on the 1st failure');

    // 1st drop already scheduled a reconnect. Now make reconnects fail.
    transport.statusCode = 503;
    scheduler.flush(); // fires reconnect → connect 503 → failure 2
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(mgr.state.connectionDown, isTrue);
    // No genuine push-gate edge on the 2nd failure (already down), but the
    // FSM still force-emits NotifyPushDisabled on every retryable failure;
    // the receiver (SyncManager.startPolling) is what
    // must treat the repeat as a no-op, not the FSM.
    expect(pollCount, 2);
  });

  test('reconnect dedup: repeated errors do not stack pending reconnects',
      () async {
    transport.statusCode = 503;
    final mgr = build(FakeAuthProvider(_pushCredential()));

    await mgr.start();
    await Future<void>.delayed(Duration.zero);
    // Only one reconnect pending even though more errors could arrive.
    expect(scheduler.pendingCount, 1);
  });

  test('backoff grows across reconnect attempts', () async {
    transport.statusCode = 503;
    final mgr = build(FakeAuthProvider(_pushCredential()));

    await mgr.start();
    await Future<void>.delayed(Duration.zero);
    final first = scheduler.pendingDelays.single;
    scheduler.flush();
    await Future<void>.delayed(Duration.zero);
    final second = scheduler.pendingDelays.single;

    expect(first, const Duration(milliseconds: 1000));
    expect(second, const Duration(milliseconds: 2000));
  });

  test('SPLIT_UPDATE fetchRequired → flags fetch triggered', () async {
    transport.statusCode = 200;
    // pcn mismatch (store cn is 0, pcn is 99) forces fetchRequired.
    transport.lines = _messageFrame({
      'type': 'SPLIT_UPDATE',
      'changeNumber': 100,
      'pcn': 99,
      'c': 0,
      'd': 'x',
    });
    final mgr = build(FakeAuthProvider(_pushCredential()));

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 1 catch-up on connect + 1 from the notification.
    expect(flagsFetchCount, greaterThanOrEqualTo(2));
  });

  test('membership UNBOUNDED → jitter delay applied then fetch', () async {
    transport.statusCode = 200;
    transport.lines = _messageFrame({
      'type': 'MEMBERSHIPS_MS_UPDATE',
      'u': 0, // UNBOUNDED
      'cn': 5,
      'i': 1000,
      'h': 1,
      's': 42,
    });
    final mgr = build(FakeAuthProvider(_pushCredential()));

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final membershipsAfterConnect = membershipsFetchCount;
    // A jitter fetch is pending on the scheduler (not yet fired).
    expect(scheduler.pendingCount, greaterThanOrEqualTo(1));
    scheduler.flush();
    await Future<void>.delayed(Duration.zero);
    expect(membershipsFetchCount, greaterThan(membershipsAfterConnect));
  });

  group('compressed notifications', () {
    const inBitmap = '88f8b33b-f858-4aea-bea2-a5f066bab3ce';
    const notInBitmap = '88f8b33b-f858-4aea-bea2-a5f066bab3c0';

    Future<void> run(StreamingManager mgr) async {
      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      scheduler.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    StreamingManager buildForKeys(List<String> keys, List<String> fetchedKeys,
        {SplitLogger? logger}) {
      final client = MockClient((request) async {
        if (request.url.path.contains('memberships')) {
          fetchedKeys.add(request.url.path.split('/').last);
        }
        return http.Response(jsonEncode({'ms': {}, 'ls': {}}), 200);
      });
      final fetcher = MembershipsFetcher(
        httpClient: SplitHttpClient(
            sdkVersion: 'dart_test-1.0.0', apiKey: 'sdk-key', client: client),
        log: log,
        baseUrl: 'https://sdk.example',
        processor: MembershipsProcessor(membershipStore: membershipStore),
      );
      keys.forEach(fetcher.bindKey);
      return StreamingManager(
        transport: transport,
        authProvider: FakeAuthProvider(_pushCredential()),
        flagsFetcher: flagsFetcher,
        membershipsFetcher: fetcher,
        ruleStore: ruleStore,
        rbsStore: rbsStore,
        membershipStore: membershipStore,
        streamingBaseUri: Uri.parse('https://streaming.example'),
        logger: logger ?? log,
        scheduler: scheduler,
        clock: clock,
        matchingKeys: () => keys,
      );
    }

    Map<String, dynamic> bounded(String d) => {
          'type': 'MEMBERSHIPS_MS_UPDATE',
          'u': 1,
          'cn': 5,
          'c': 1,
          'd': d,
          'h': 0
        };

    test('gzip SPLIT_UPDATE with pcn == stored applies in place', () async {
      transport.statusCode = 200;
      transport.keepOpen = true;
      transport.lines = _messageFrame({
        'type': 'SPLIT_UPDATE',
        'changeNumber': jsSplit0ChangeNumber,
        // The mock /splitChanges catch-up leaves the store at change 10.
        'pcn': 10,
        'c': 1,
        'd': jsSplit0C1,
      });
      final updated = <List<String>>[];
      final mgr = StreamingManager(
        transport: transport,
        authProvider: FakeAuthProvider(_pushCredential()),
        flagsFetcher: flagsFetcher,
        ruleStore: ruleStore,
        rbsStore: rbsStore,
        streamingBaseUri: Uri.parse('https://streaming.example'),
        logger: log,
        scheduler: scheduler,
        clock: clock,
        onFlagsUpdated: updated.add,
      );

      await run(mgr);

      expect(updated.expand((e) => e), contains(jsSplit0Name));
      await mgr.stop();
    });

    test('gzip BOUNDED: fetches for the key whose bit is set only', () async {
      transport.statusCode = 200;
      transport.keepOpen = true;
      transport.lines = _messageFrame(bounded(jsBitmap0Gzip));
      final fetchedKeys = <String>[];
      final mgr = buildForKeys([inBitmap, notInBitmap], fetchedKeys);

      await run(mgr);

      // Catch-up fetches both keys once; only the targeted key is fetched
      // again for the notification.
      expect(fetchedKeys.where((k) => k == inBitmap).length, 2);
      expect(fetchedKeys.where((k) => k == notInBitmap).length, 1);
      await mgr.stop();
    });

    test('malformed BOUNDED: one WARNING, unbounded fetch for each key',
        () async {
      transport.statusCode = 200;
      transport.keepOpen = true;
      transport.lines = _messageFrame(bounded(malformedBounded));
      final fetchedKeys = <String>[];
      final mgr = buildForKeys(['k1', 'k2'], fetchedKeys,
          logger: SplitLogger(level: LogLevel.warning));
      final logs = <String>[];
      await runZoned(() => run(mgr),
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => logs.add(line),
          ));

      final warnings = logs.where(
          (l) => l.contains('Fetching Memberships due to an error processing '
              'BoundedFetchRequest notification'));
      expect(warnings, hasLength(1));
      // catch-up fetch + one notification fetch per key.
      expect(fetchedKeys.where((k) => k == 'k1').length, 2);
      expect(fetchedKeys.where((k) => k == 'k2').length, 2);
      await mgr.stop();
    });
  });

  test('CONTROL STREAMING_PAUSED → poll; STREAMING_RESUMED → push', () async {
    transport.statusCode = 200;
    // Hold the connection open after the two control frames: the stream
    // naturally ending is itself a retryable failure that now
    // unconditionally drops connectionDown (§11.3), which would otherwise
    // flip push back down right after STREAMING_RESUMED and break the
    // final isPushUp assertion.
    transport.keepOpen = true;
    var pushEnabledCount = 0;
    var pushDisabledCount = 0;
    transport.lines = [
      ..._messageFrame({
        'type': 'CONTROL',
        'controlType': 'STREAMING_PAUSED',
        'timestamp': 10
      }),
      ..._messageFrame({
        'type': 'CONTROL',
        'controlType': 'STREAMING_RESUMED',
        'timestamp': 20
      }),
    ];
    final mgr = build(FakeAuthProvider(_pushCredential()),
        onPushEnabled: () => pushEnabledCount++,
        onPushDisabled: () => pushDisabledCount++);

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(pushDisabledCount, greaterThanOrEqualTo(1));
    // Enabled once on connect + once on resume.
    expect(pushEnabledCount, greaterThanOrEqualTo(2));
    expect(mgr.isPushUp, isTrue);
  });

  test('OCCUPANCY publishers=0 → push down; >0 → push up', () async {
    transport.statusCode = 200;
    // Hold the connection open after the two occupancy frames — see the
    // CONTROL test above for why (§11.3).
    transport.keepOpen = true;
    var pushDisabled = 0;
    var pushEnabled = 0;
    transport.lines = [
      ..._messageFrame({
        'type': 'OCCUPANCY',
        'metrics': {'publishers': 0}
      }),
      ..._messageFrame({
        'type': 'OCCUPANCY',
        'metrics': {'publishers': 2}
      }),
    ];
    final mgr = build(FakeAuthProvider(_pushCredential()),
        onPushEnabled: () => pushEnabled++,
        onPushDisabled: () => pushDisabled++);

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(pushDisabled, greaterThanOrEqualTo(1));
    expect(pushEnabled, greaterThanOrEqualTo(2));
    expect(mgr.isPushUp, isTrue);
  });

  group('proactive token refresh (§11.3)', () {
    // A push credential expiring [ttl] after epoch 0 (the FakeClock's start).
    JwtCredential expiringCredential(Duration ttl) => JwtCredential(
          token: 'tok-123',
          channels: const ['ch1'],
          pushEnabled: true,
          expiresAt: ttl.inSeconds,
          connDelaySeconds: 0,
        );

    test('schedules refresh at expiresAt − 10min after a healthy connect',
        () async {
      transport.statusCode = 200;
      transport.keepOpen = true; // stable connection, no reconnect noise
      // Token valid for 1 hour from epoch 0 → refresh 10 min before = 50 min.
      final mgr = build(FakeAuthProvider(expiringCredential(
        const Duration(hours: 1),
      )));

      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The only pending timer is the refresh (connection is held open).
      expect(scheduler.pendingCount, 1);
      expect(scheduler.pendingDelays.single, const Duration(minutes: 50));
    });

    test('short TTL clamps the refresh delay to the minimum', () async {
      transport.statusCode = 200;
      transport.keepOpen = true;
      // exp = now + 60s → expiresAt − 10min is in the past → clamp to 1s.
      final mgr = build(FakeAuthProvider(expiringCredential(
        const Duration(seconds: 60),
      )));

      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(scheduler.pendingCount, 1);
      expect(scheduler.pendingDelays.single, const Duration(seconds: 1));
    });

    test('refresh timer invalidates the token and reconnects', () async {
      transport.statusCode = 200;
      transport.keepOpen = true;
      final auth = FakeAuthProvider(expiringCredential(
        const Duration(seconds: 60),
      ));
      final mgr = build(auth);

      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final connectsBefore = transport.connectCount;

      scheduler.flush(); // fire the refresh timer
      await Future<void>.delayed(const Duration(milliseconds: 10));
      scheduler.flush(); // fire the reconnect it scheduled
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(auth.invalidateCount, greaterThanOrEqualTo(1),
          reason: 'refresh MUST invalidate the token');
      expect(transport.connectCount, greaterThan(connectsBefore),
          reason: 'refresh MUST reconnect to pull a fresh JWT');
    });

    test('only one refresh timer is pending at a time (dedup)', () async {
      transport.statusCode = 200;
      transport.keepOpen = true;
      final mgr = build(FakeAuthProvider(expiringCredential(
        const Duration(hours: 1),
      )));

      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(scheduler.pendingCount, 1);

      // Fire the refresh; it invalidates + reconnects. After the reconnect
      // re-opens the socket, exactly one fresh refresh timer must be armed —
      // never two stacked.
      scheduler.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      scheduler.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(scheduler.pendingCount, 1,
          reason: 'a reconnect must not stack a second refresh timer');
    });

    test('stop cancels the pending refresh timer', () async {
      transport.statusCode = 200;
      transport.keepOpen = true;
      final mgr = build(FakeAuthProvider(expiringCredential(
        const Duration(hours: 1),
      )));

      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(scheduler.pendingCount, 1);

      await mgr.stop();
      expect(scheduler.pendingCount, 0,
          reason: 'stop MUST cancel the proactive refresh timer');
    });

    test('connection drop cancels the refresh timer (rescheduled on reconnect)',
        () async {
      // Healthy connect (refresh armed), then the stream ends → retryable drop.
      // First drop keeps push up but a second failure would drop the axis;
      // regardless, the socket teardown cancels the pending refresh.
      transport.statusCode = 200;
      final mgr = build(FakeAuthProvider(expiringCredential(
        const Duration(hours: 1),
      )));

      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // After the empty stream ends, onDone → SocketError → reconnect armed;
      // the refresh from the initial open was cancelled on socket close. The
      // pending timer is the reconnect, not a stale refresh.
      expect(scheduler.pendingDelays, contains(const Duration(seconds: 1)),
          reason: 'a reconnect (1s backoff) is pending, not the 50min refresh');
      expect(
          scheduler.pendingDelays, isNot(contains(const Duration(minutes: 50))),
          reason:
              'the proactive refresh MUST be cancelled when the socket drops');
    });
  });

  test('stop closes socket, cancels reconnect, idempotent', () async {
    transport.statusCode = 503;
    final mgr = build(FakeAuthProvider(_pushCredential()));

    await mgr.start();
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.pendingCount, 1);

    await mgr.stop();
    expect(scheduler.pendingCount, 0);
    expect(mgr.state.connState, ConnState.stopped);

    // Idempotent.
    await mgr.stop();
    expect(mgr.state.connState, ConnState.stopped);
  });

  test(
      'RB_SEGMENT_UPDATE always triggers a full flags fetch (in-place RBS deferred)',
      () async {
    transport.statusCode = 200;
    transport.lines = _messageFrame({
      'type': 'RB_SEGMENT_UPDATE',
      'changeNumber': 100,
      'pcn': 0,
      'c': 0,
      'd': 'x',
    });
    final mgr = build(FakeAuthProvider(_pushCredential()));

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 1 catch-up fetch on connect + 1 full fetch from RB_SEGMENT_UPDATE.
    // In-place RBS apply is out of scope for this increment, so the manager
    // always falls back to a safe /splitChanges fetch for this type.
    expect(flagsFetchCount, greaterThanOrEqualTo(2));
  });

  test('SEGMENT_UPDATE dispatches a fetch for the named segment (server-side)',
      () async {
    transport.statusCode = 200;
    transport.lines = _messageFrame({
      'type': 'SEGMENT_UPDATE',
      'changeNumber': 100,
      'segmentName': 'my-seg',
    });
    final fetched = <String>[];
    final mgr = build(
      FakeAuthProvider(_pushCredential()),
      segmentFetcher: (name) async {
        fetched.add(name);
        return true;
      },
    );

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fetched, ['my-seg']);
  });

  test('SEGMENT_UPDATE without a segmentFetcher is ignored (client-side)',
      () async {
    transport.statusCode = 200;
    // Hold the connection open — see the CONTROL test above for why (§11.3):
    // the final assertion checks isPushUp stays true, so the stream must
    // not be allowed to naturally end and drop the connection axis.
    transport.keepOpen = true;
    transport.lines = _messageFrame({
      'type': 'SEGMENT_UPDATE',
      'changeNumber': 100,
      'segmentName': 'my-seg',
    });
    // No segmentFetcher provided → routed as a no-op, no crash.
    final mgr = build(FakeAuthProvider(_pushCredential()));

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The frame is processed and ignored — the connection stays healthy.
    expect(mgr.isPushUp, isTrue);
  });

  test('SEGMENT_UPDATE with missing segmentName is dropped (no fetch)',
      () async {
    transport.statusCode = 200;
    transport.lines = _messageFrame({
      'type': 'SEGMENT_UPDATE',
      'changeNumber': 100,
      // segmentName omitted
    });
    final fetched = <String>[];
    final mgr = build(
      FakeAuthProvider(_pushCredential()),
      segmentFetcher: (name) async {
        fetched.add(name);
        return true;
      },
    );

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fetched, isEmpty);
  });

  test(
      'reconnect during in-flight credential fetch opens only one socket (TOCTOU)',
      () async {
    transport.statusCode = 200;
    // Hold the connection open — the final assertion checks isPushUp stays
    // true, so the default empty-lines stream must not be allowed to
    // naturally end and drop the connection axis (§11.3). This test is
    // about dedup of the credential fetch, not socket-drop behavior.
    transport.keepOpen = true;
    final auth = GatedAuthProvider(_pushCredential());
    final mgr = build(auth);

    // First connect: start() suspends inside the gated credential fetch.
    final firstStart = mgr.start();
    await Future<void>.delayed(Duration.zero);
    expect(auth.credentialCount, 1);
    expect(transport.connectCount, 0, reason: 'auth still in flight');

    // A reconnect fires while the first auth fetch is still pending. It bumps
    // the connect generation but is itself deduped by the _opening latch, so
    // it does NOT start a second credential fetch.
    unawaited(mgr.start());
    await Future<void>.delayed(Duration.zero);
    expect(auth.credentialCount, 1,
        reason: 'second connect deduped by _opening latch');

    // Release the in-flight credential fetch; the (only) attempt completes.
    auth.releaseAll();
    await firstStart;
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Exactly one socket ultimately active; no stale _client overwrite.
    expect(transport.connectCount, 1);
    expect(mgr.isPushUp, isTrue);
  });

  test('malformed notification does not kill the manager', () async {
    transport.statusCode = 200;
    transport.lines = [
      'event: message',
      'data: not-json',
      '',
      ..._messageFrame({
        'type': 'CONTROL',
        'controlType': 'STREAMING_PAUSED',
        'timestamp': 10
      }),
    ];
    var polled = false;
    final mgr = build(FakeAuthProvider(_pushCredential()),
        onPushDisabled: () => polled = true);

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // The valid pause frame after the bad frame still processes.
    expect(polled, isTrue);
  });

  group('logging', () {
    // Runs [body] capturing everything the logger prints, returning the lines.
    Future<List<String>> captureLogs(Future<void> Function() body) async {
      final lines = <String>[];
      await runZoned(
        body,
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => lines.add(line),
        ),
      );
      return lines;
    }

    final verbose = SplitLogger(level: LogLevel.verbose);

    test('verbose logs the connect, connect status and each SSE frame',
        () async {
      transport.statusCode = 200;
      transport.lines = _messageFrame({
        'type': 'SPLIT_UPDATE',
        'changeNumber': 42,
      });
      final logs = await captureLogs(() async {
        final mgr = build(FakeAuthProvider(_pushCredential()), logger: verbose);
        await mgr.start();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });

      expect(logs.any((l) => l.contains('opening SSE socket')), isTrue);
      expect(logs.any((l) => l.contains('SSE connect status 200')), isTrue);
      expect(logs.any((l) => l.contains('SSE frame received')), isTrue);
      expect(logs.any((l) => l.contains('SPLIT_UPDATE')), isTrue);
    });

    test('verbose connect log redacts the access token', () async {
      transport.statusCode = 200;
      final logs = await captureLogs(() async {
        final mgr = build(FakeAuthProvider(_pushCredential()), logger: verbose);
        await mgr.start();
        await Future<void>.delayed(Duration.zero);
      });

      final connectLine =
          logs.firstWhere((l) => l.contains('connecting to'), orElse: () => '');
      expect(connectLine, isNotEmpty);
      // The token value is redacted; it is URL-encoded in the rendered Uri.
      expect(connectLine, contains('accessToken=%3Credacted%3E'));
      expect(connectLine, isNot(contains('tok-123')));
    });

    test('silent logger (LogLevel.none) emits nothing', () async {
      transport.statusCode = 200;
      transport.lines = _messageFrame({
        'type': 'SPLIT_UPDATE',
        'changeNumber': 42,
      });
      final logs = await captureLogs(() async {
        final mgr = build(FakeAuthProvider(_pushCredential()),
            logger: SplitLogger(level: LogLevel.none));
        await mgr.start();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });

      expect(logs, isEmpty);
    });
  });

  // Server-side topology (spec Axis 3, §17.2): no per-key memberships. The
  // MembershipsFetcher + MembershipStore MUST be optional; MEMBERSHIPS_* frames
  // are ignored and catch-up runs the flags fetch only. This mirrors
  // `javascript-commons/sync/streaming/pushManager.ts`, which only subscribes
  // MEMBERSHIPS_* handlers when a `userKey` is bound.
  group('server-side topology (no memberships)', () {
    StreamingManager buildServerSide(AuthProvider auth) {
      return StreamingManager(
        transport: transport,
        authProvider: auth,
        flagsFetcher: flagsFetcher,
        // No membershipsFetcher, no membershipStore.
        ruleStore: ruleStore,
        rbsStore: rbsStore,
        streamingBaseUri: Uri.parse('https://streaming.example'),
        logger: log,
        scheduler: scheduler,
        clock: clock,
      );
    }

    test('catch-up fetches flags only (no memberships)', () async {
      transport.statusCode = 200;
      transport.lines = [':keepalive'];
      // Hold the connection open — the final assertion checks isPushUp
      // stays true (§11.3); see the CONTROL test above for why.
      transport.keepOpen = true;

      final mgr = buildServerSide(FakeAuthProvider(_pushCredential()));
      await mgr.start();
      await Future<void>.delayed(Duration.zero);

      expect(flagsFetchCount, 1);
      expect(membershipsFetchCount, 0);
      expect(mgr.isPushUp, isTrue);
    });

    test('MEMBERSHIPS_MS_UPDATE is ignored (no membership strategy)', () async {
      transport.statusCode = 200;
      transport.lines = _messageFrame({
        'type': 'MEMBERSHIPS_MS_UPDATE',
        'u': 0,
        'cn': 5,
        'i': 1000,
        'h': 1,
        's': 42,
      });

      final mgr = buildServerSide(FakeAuthProvider(_pushCredential()));
      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Flush any scheduled work (jitter, token refresh) to confirm no
      // memberships fetch is queued behind them.
      scheduler.flush();
      await Future<void>.delayed(Duration.zero);
      expect(membershipsFetchCount, 0);
    });

    test('SPLIT_UPDATE still triggers a flags fetch on server-side', () async {
      transport.statusCode = 200;
      transport.lines = _messageFrame({
        'type': 'SPLIT_UPDATE',
        'changeNumber': 100,
      });

      final mgr = buildServerSide(FakeAuthProvider(_pushCredential()));
      await mgr.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 1 catch-up + 1 from the notification, memberships untouched.
      expect(flagsFetchCount, greaterThanOrEqualTo(2));
      expect(membershipsFetchCount, 0);
    });
  });
}
