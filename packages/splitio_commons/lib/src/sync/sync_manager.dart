import 'dart:async';

import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/sync.dart';

class SyncManager {
  final FlagsFetcher _flagsFetcher;
  final MembershipsFetcher _membershipsFetcher;
  final List<Recorder> _recorders;
  final SyncConfig _config;
  final SplitLogger _log;

  /// Optional streaming coordinator (task 4.7). When null, [SyncManager] is
  /// exactly the poll-only manager it was before streaming existed: backward
  /// compatible for every existing construction site.
  final StreamingManager? _streamingManager;

  Timer? _rulesTimer;
  final Map<String, Timer> _membershipsTimers = {};
  bool _polling = false;

  SyncManager({
    required SplitHttpClient httpClient,
    required InMemoryRuleStore ruleStore,
    required InMemoryRuleBasedSegmentStore rbsStore,
    required InMemoryMembershipStore membershipStore,
    required SyncConfig config,
    required String baseUrl,
    required SplitLogger logger,
    required FlagsFetcher flagsFetcher,
    required MembershipsFetcher membershipsFetcher,
    List<Recorder> recorders = const [],
    StreamingManager? streamingManager,
  })  : _config = config,
        _log = logger,
        _flagsFetcher = flagsFetcher,
        _membershipsFetcher = membershipsFetcher,
        _recorders = recorders,
        _streamingManager = streamingManager;

  /// Whether poll timers are currently active (test/observation hook).
  bool get isPolling => _polling;

  /// Number of live poll timers: the rules timer plus one per bound key
  /// (test/observation hook — used to assert no timer leaks across
  /// streaming up/down cycles).
  int get activePollTimerCount =>
      (_rulesTimer != null ? 1 : 0) + _membershipsTimers.length;

  Future<bool> initialSync(String matchingKey) async {
    _membershipsFetcher.bindKey(matchingKey);
    _log.debug('Starting initial sync for key: $matchingKey');

    final results = await Future.wait([
      _flagsFetcher.fetch(),
      _membershipsFetcher.fetchForKey(matchingKey),
    ]);

    final rulesOk = results[0];
    final membershipsOk = results[1];

    if (!rulesOk || !membershipsOk) {
      if (!rulesOk) _log.error('Initial targeting rules fetch failed');
      if (!membershipsOk) _log.error('Initial memberships fetch failed');
      return false;
    }

    _log.info('Initial sync complete');
    return true;
  }

  Future<bool> syncMembershipsFor(String matchingKey) {
    _membershipsFetcher.bindKey(matchingKey);
    if (_polling) _startMembershipsTimerFor(matchingKey);
    return _membershipsFetcher.fetchForKey(matchingKey);
  }

  void startPolling() {
    _log.debug(
        'Starting polling (rules: ${_config.featureFlagsPollingRate}s, memberships: ${_config.segmentsPollingRate}s)');
    _polling = true;
    // Idempotent: cancel any existing rules timer before recreating so repeated
    // startPolling() calls (e.g. streaming down → up → down cycles) never leak a
    // timer. Membership timers already dedup via containsKey.
    _rulesTimer?.cancel();
    _rulesTimer = Timer.periodic(
      Duration(seconds: _config.featureFlagsPollingRate),
      (_) => _flagsFetcher.fetch(),
    );
    for (final key in _membershipsFetcher.boundKeys) {
      _startMembershipsTimerFor(key);
    }
  }

  /// Begins syncing in the SDK's preferred mode (spec §8.4). When a
  /// [StreamingManager] is injected, streaming is started (and, once push is
  /// confirmed up, its callbacks stop the poll timers). When no streaming
  /// manager is present, this falls back to plain polling so a streaming-less
  /// build still syncs. Off the readiness critical path (§8.1/§8.2):
  /// fire-and-forget, never blocks.
  Future<void> startStreaming() async {
    final streaming = _streamingManager;
    if (streaming == null) {
      startPolling();
      return;
    }
    await streaming.start();
  }

  /// Stops streaming (if present) without touching poll timers. Idempotent.
  Future<void> stopStreaming() async {
    await _streamingManager?.stop();
  }

  /// Push (streaming) came up (spec §8.4): stop the poll timers but keep the
  /// streaming connection. Does NOT mark the manager permanently stopped —
  /// [onStreamingDown] can bring polling back. Idempotent and safe to call
  /// repeatedly.
  void onStreamingUp() {
    _log.debug('Streaming up: stopping poll timers');
    _cancelPollTimers();
  }

  /// Push (streaming) went down / was disabled (spec §8.4): (re)start polling.
  /// Idempotent via [startPolling]; repeated calls do not leak timers.
  void onStreamingDown() {
    _log.debug('Streaming down: (re)starting polling');
    startPolling();
  }

  void _cancelPollTimers() {
    _rulesTimer?.cancel();
    _rulesTimer = null;
    for (final t in _membershipsTimers.values) {
      t.cancel();
    }
    _membershipsTimers.clear();
    _polling = false;
  }

  void _startMembershipsTimerFor(String key) {
    if (_membershipsTimers.containsKey(key)) return;
    _membershipsTimers[key] = Timer.periodic(
      Duration(seconds: _config.segmentsPollingRate),
      (_) => _membershipsFetcher.fetchForKey(key),
    );
  }

  void startRecorders() {
    _log.debug('Starting ${_recorders.length} recorder(s)');
    for (final recorder in _recorders) {
      recorder.start();
    }
  }

  Future<void> stopRecorders() async {
    for (final recorder in _recorders) {
      recorder.stop();
    }
  }

  Future<void> flushRecorders() async {
    await Future.wait(_recorders.map((r) => r.flush()));
  }

  /// Stops all sync: cancels poll timers AND stops streaming (if present).
  /// Idempotent — safe to call multiple times.
  void stop() {
    _cancelPollTimers();
    unawaited(_streamingManager?.stop());
  }
}
