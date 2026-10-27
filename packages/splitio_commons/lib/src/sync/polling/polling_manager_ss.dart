import 'dart:async';

import 'package:splitio_commons/src/sync/polling/polling_manager.dart';

/// Server-side polling: one feature-flags timer and one segment-changes timer
/// (spec §8.4, §10). Mirrors JS `pollingManagerSS`.
class PollingManagerSS implements PollingManager {
  final Future<bool> Function() _fetchFlags;
  final Future<bool> Function() _fetchSegments;
  final Duration _featuresRefreshRate;
  final Duration _segmentsRefreshRate;

  Timer? _flagsTimer;
  Timer? _segmentsTimer;
  bool _running = false;

  PollingManagerSS({
    required Future<bool> Function() fetchFlags,
    required Future<bool> Function() fetchSegments,
    required Duration featuresRefreshRate,
    required Duration segmentsRefreshRate,
  })  : _fetchFlags = fetchFlags,
        _fetchSegments = fetchSegments,
        _featuresRefreshRate = featuresRefreshRate,
        _segmentsRefreshRate = segmentsRefreshRate;

  @override
  bool get isRunning => _running;

  /// Flags first (populates the rule store so the segments fetch knows which
  /// segments to poll), then segments. Segments are fetched even when flags
  /// fail (no short-circuit). Returns true only when both succeed.
  @override
  Future<bool> syncAll() async {
    final flagsOk = await _fetchFlags();
    final segmentsOk = await _fetchSegments();
    return flagsOk && segmentsOk;
  }

  @override
  void start() {
    // True idempotency (§11.3): once polling is already running, repeated
    // calls (e.g. one per retryable streaming failure while streaming never
    // comes up) MUST NOT touch the existing timers. Cancelling and recreating
    // the periodic timers on every call resets their elapsed time toward the
    // next fire, so a failure cadence faster than the poll period would
    // starve them forever.
    if (_running) return;
    _running = true;
    _flagsTimer = Timer.periodic(_featuresRefreshRate, (_) => _fetchFlags());
    _segmentsTimer =
        Timer.periodic(_segmentsRefreshRate, (_) => _fetchSegments());
  }

  @override
  void stop() {
    _flagsTimer?.cancel();
    _flagsTimer = null;
    _segmentsTimer?.cancel();
    _segmentsTimer = null;
    _running = false;
  }
}
