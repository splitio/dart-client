/// Read-only lifecycle state the shared client core consults per call.
/// Implemented by each flavor's client; never cached by the core.
abstract interface class ClientState {
  /// This client instance was destroyed (`destroy()` ran).
  bool get isClientDestroyed;

  /// The client's EventsManager was disposed (factory teardown).
  bool get isEventsDestroyed;

  /// The client is READY (spec §8.2).
  bool get isReady;
}
