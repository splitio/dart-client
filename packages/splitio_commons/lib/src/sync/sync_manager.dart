import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/sync/polling/polling_manager.dart';
import 'package:splitio_commons/src/sync/sync.dart';

/// Flavor-agnostic sync coordinator shared by the client-side and server-side
/// SDKs. Decides *when* to poll, stream and run recorders; the injected
/// [PollingManager] decides *what* polling fetches (spec §8.4, §10).
class SyncManager {
  final PollingManager _polling;
  final List<Recorder> _recorders;
  final SplitLogger _log;

  /// Optional streaming coordinator (task 4.7). When null, [SyncManager] is
  /// exactly the poll-only manager it was before streaming existed: backward
  /// compatible for every existing construction site.
  final StreamingManager? _streamingManager;

  /// Set at the start of [stop]. Once true, [startPolling] (and therefore
  /// [onStreamingDown]) is a no-op — guards against a push-down callback
  /// (triggered by [stop] itself tearing down a streaming connection that was
  /// up) racing the poll-timer cancellation and restarting timers that would
  /// otherwise outlive [stop].
  bool _stopped = false;

  SyncManager({
    required PollingManager polling,
    required SplitLogger logger,
    List<Recorder> recorders = const [],
    StreamingManager? streamingManager,
  })  : _polling = polling,
        _log = logger,
        _recorders = recorders,
        _streamingManager = streamingManager;

  /// Whether poll timers are currently active (test/observation hook).
  bool get isPolling => _polling.isRunning;

  /// Fetches every feed once via the injected [PollingManager] (spec §8.1).
  Future<bool> initialSync() => _polling.syncAll();

  void startPolling() {
    // Defensive: no-op once stopped, even if called directly.
    if (_stopped) return;
    // True idempotency (§11.3): the polling manager's start() is a no-op
    // while already running, so repeated calls never touch existing timers.
    if (_polling.isRunning) return;
    _polling.start();
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
    _polling.stop();
  }

  /// Push (streaming) went down / was disabled (spec §8.4): (re)start polling.
  /// Idempotent via [startPolling]; repeated calls do not leak timers. No-op
  /// once [stop] has been called — a push-down callback MUST NOT resurrect
  /// polling during or after teardown.
  void onStreamingDown() {
    if (_stopped) return;
    _log.debug('Streaming down: (re)starting polling');
    startPolling();
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
  ///
  /// Marks the manager stopped BEFORE awaiting streaming shutdown so a
  /// push-down callback (streaming was up → [StreamingManager.stop] emits
  /// NotifyPushDisabled → [onStreamingDown]) firing mid-teardown finds
  /// [onStreamingDown] already a no-op. The poll timers are cancelled again
  /// after the await as a second, defensive guard.
  Future<void> stop() async {
    _stopped = true;
    _polling.stop();
    await _streamingManager?.stop();
    _polling.stop();
  }
}
