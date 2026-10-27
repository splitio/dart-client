import 'dart:async';
import 'dart:io';

import 'package:splitio_commons/src/logger/logger.dart';

/// SIGTERM / SIGINT auto-flush hook for server-side lifecycles.
///
/// On first signal delivery:
///   1. Cancels its subscriptions (so a second signal is a no-op).
///   2. Awaits [_onSignal] (typically `factory.destroy()`).
///   3. Calls [_exitFn] with `0`.
///
/// The [_signals] streams and [_exitFn] are injected so unit tests can
/// simulate signals without touching real `dart:io`. Production callers
/// use [SignalListener.forDefaults] which wires both SIGTERM and SIGINT
/// via `ProcessSignal.watch()` and defaults [_exitFn] to `exit`.
///
/// Each source is subscribed directly so [dispose] releases the underlying
/// `ProcessSignal` watchers. While a watcher is subscribed, Dart suppresses
/// the signal's default action, so a leaked one would keep SIGINT/SIGTERM
/// from terminating the process after the factory is destroyed.
///
/// Platform note: `ProcessSignal.watch()` throws on unsupported platforms
/// (Flutter Web, some Fuchsia builds). [install] catches and logs a
/// warning; the SDK stays functional, just without auto-flush.
class SignalListener {
  final List<Stream<int>> _signals;
  final Future<void> Function() _onSignal;
  final void Function(int) _exitFn;
  final SplitLogger? _log;

  final List<StreamSubscription<int>> _subs = [];
  bool _handled = false;

  SignalListener({
    required List<Stream<int>> signals,
    required Future<void> Function() onSignal,
    required void Function(int) exitFn,
    SplitLogger? logger,
  })  : _signals = signals,
        _onSignal = onSignal,
        _exitFn = exitFn,
        _log = logger;

  /// Production factory: subscribes to both SIGTERM and SIGINT via
  /// `dart:io` and defaults [exitFn] to `exit`.
  factory SignalListener.forDefaults({
    required Future<void> Function() onSignal,
    SplitLogger? logger,
    void Function(int)? exitFn,
  }) {
    return SignalListener(
      signals: _defaultSignals(),
      onSignal: onSignal,
      exitFn: exitFn ?? exit,
      logger: logger,
    );
  }

  void install() {
    for (final signals in _signals) {
      try {
        _subs.add(signals.listen(_handle, onError: _onUnsupported));
      } catch (e) {
        _onUnsupported(e);
      }
    }
  }

  Future<void> _handle(int signalNumber) async {
    if (_handled) return;
    _handled = true;
    _log?.info('Received signal $signalNumber — flushing and exiting');
    await dispose();
    try {
      await _onSignal();
    } catch (e, s) {
      _log?.error('Error during signal-triggered destroy: $e\n$s');
    }
    _exitFn(0);
  }

  void _onUnsupported(Object e) {
    _log?.warning(
        'SignalListener could not install on this platform: $e — running without auto-flush');
  }

  Future<void> dispose() async {
    final subs = List.of(_subs);
    _subs.clear();
    await Future.wait(subs.map((s) => s.cancel()));
  }
}

List<Stream<int>> _defaultSignals() => [
      ProcessSignal.sigterm.watch().map((_) => 15),
      ProcessSignal.sigint.watch().map((_) => 2),
    ];
