import 'dart:async';

/// Minimal time SPI (spec §6, Axis 1): wall-clock reads, kept behind an
/// interface so tests can drive time deterministically.
///
/// The streaming runtime does not read the wall clock directly so that tests
/// never depend on real time. Production wiring supplies [SystemClock].
abstract class Clock {
  /// The current wall-clock time.
  DateTime now();
}

/// Real [Clock] backed by [DateTime.now]. Free of `dart:io`.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Minimal timer SPI (spec §6, Axis 1): schedule a one-shot callback after a
/// delay and cancel it by handle, kept behind an interface so reconnect backoff
/// and sync-delay jitter can be driven deterministically in tests.
///
/// Implementations MUST invoke the callback at most once and MUST make [cancel]
/// idempotent (cancelling an already-fired or unknown handle is a no-op).
abstract class Scheduler {
  /// Schedules [callback] to run after [delay]. Returns an opaque handle usable
  /// with [cancel]. A [delay] of [Duration.zero] still defers to a later turn.
  Object schedule(Duration delay, void Function() callback);

  /// Cancels a pending callback by its [handle]. No-op if it already fired or
  /// the handle is unknown.
  void cancel(Object handle);
}

/// Real [Scheduler] backed by `dart:async` [Timer]. Free of `dart:io`, so it
/// runs on every Dart target (VM, Flutter, web).
class SystemScheduler implements Scheduler {
  const SystemScheduler();

  @override
  Object schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);

  @override
  void cancel(Object handle) {
    if (handle is Timer) handle.cancel();
  }
}
