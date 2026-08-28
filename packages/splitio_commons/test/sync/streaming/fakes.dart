import 'package:splitio_commons/src/sync/streaming/clock.dart';

/// A [Clock] whose current time is settable, for deterministic tests.
class FakeClock implements Clock {
  DateTime current;

  FakeClock([DateTime? start])
      : current = start ?? DateTime.fromMillisecondsSinceEpoch(0);

  void advance(Duration by) => current = current.add(by);

  @override
  DateTime now() => current;
}

/// A pending entry scheduled on a [FakeScheduler].
class _Pending {
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  _Pending(this.delay, this.callback);
}

/// A [Scheduler] that never uses real timers: pending callbacks are held until
/// explicitly [flush]ed (fire all live entries) so tests are deterministic.
class FakeScheduler implements Scheduler {
  final List<_Pending> _pending = [];

  /// Number of live (not yet fired, not cancelled) pending callbacks.
  int get pendingCount => _pending.where((p) => !p.cancelled).length;

  /// The delays of all live pending callbacks, in scheduling order.
  List<Duration> get pendingDelays =>
      _pending.where((p) => !p.cancelled).map((p) => p.delay).toList();

  @override
  Object schedule(Duration delay, void Function() callback) {
    final entry = _Pending(delay, callback);
    _pending.add(entry);
    return entry;
  }

  @override
  void cancel(Object handle) {
    if (handle is _Pending) handle.cancelled = true;
  }

  /// Fires every live pending callback once, in scheduling order. Callbacks
  /// scheduled *during* the flush are not fired until the next [flush].
  void flush() {
    final live = _pending.where((p) => !p.cancelled).toList();
    _pending.clear();
    for (final entry in live) {
      if (!entry.cancelled) entry.callback();
    }
  }
}
