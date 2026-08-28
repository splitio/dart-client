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
    final httpClient = SplitHttpClient(apiKey: 'sdk-key', client: mockClient);
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
  }) {
    return StreamingManager(
      transport: transport,
      authProvider: auth,
      flagsFetcher: flagsFetcher,
      membershipsFetcher: membershipsFetcher,
      ruleStore: ruleStore,
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

  test('after connect, 1st failure schedules reconnect without poll fallback',
      () async {
    // Connect succeeds first (empty stream → onDone → retryable drop = fail 1).
    transport.statusCode = 200;
    var pollCount = 0;
    final mgr = build(FakeAuthProvider(_pushCredential()),
        onPushDisabled: () => pollCount++);

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // 1st drop after a healthy connect: reconnect armed, still push-up.
    expect(scheduler.pendingCount, 1);
    expect(pollCount, 0, reason: '1 failure must not trigger poll fallback');
    expect(mgr.state.connectionDown, isFalse);
  });

  test('2nd consecutive failure → connectionDown → poll fallback', () async {
    // Healthy connect first, then failing reconnects.
    transport.statusCode = 200;
    var pollCount = 0;
    final mgr = build(FakeAuthProvider(_pushCredential()),
        onPushDisabled: () => pollCount++);

    await mgr.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // 1st drop already scheduled a reconnect. Now make reconnects fail.
    transport.statusCode = 503;
    scheduler.flush(); // fires reconnect → connect 503 → failure 2
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(mgr.state.connectionDown, isTrue);
    expect(pollCount, greaterThanOrEqualTo(1));
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

  test('CONTROL STREAMING_PAUSED → poll; STREAMING_RESUMED → push', () async {
    transport.statusCode = 200;
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

  test(
      'reconnect during in-flight credential fetch opens only one socket (TOCTOU)',
      () async {
    transport.statusCode = 200;
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
}
