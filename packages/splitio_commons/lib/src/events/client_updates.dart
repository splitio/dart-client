import 'dart:async';

/// Per-client view of the shared [EventsManager.onUpdated] stream.
///
/// Several clients can share one `EventsManager`, but spec §8.2 requires
/// that destroying a client closes *its* `whenUpdated()` stream without
/// affecting the others (mirrors the JS SDK, where each client owns its
/// own update emitter). [close] ends only this view; disposing the shared
/// manager closes every view.
class ClientUpdates {
  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();
  late final StreamSubscription<List<String>> _source;

  ClientUpdates(Stream<List<String>> source) {
    _source = source.listen(_controller.add, onDone: close);
  }

  Stream<List<String>> get stream => _controller.stream;

  /// Stops forwarding and closes [stream] (subscribers receive `onDone`).
  /// Idempotent.
  Future<void> close() async {
    if (_controller.isClosed) return;
    // Not awaited: a broadcast controller's close() future waits for every
    // listener to receive `onDone`, which a paused subscriber could delay
    // indefinitely — destroy() MUST NOT hang on application code.
    unawaited(_controller.close());
    await _source.cancel();
  }
}
