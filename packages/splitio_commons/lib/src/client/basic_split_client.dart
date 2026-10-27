/// The shared lifecycle surface for both client-side and server-side
/// SDK clients. Mirrors the JavaScript SDK's `IBasicClient` interface
/// (javascript-commons `types/splitio.d.ts` — `IBasicClient` extends the
/// status/lifecycle surface that every flavor shares).
///
/// Treatment and track methods stay on flavor-specific subtypes (CS's
/// `SplitClient`, SS's `ServerSplitClient`) because their signatures
/// differ: client-side bakes the user key into the client (methods take
/// a flag positional first), whereas server-side is single-tenant and
/// takes the key per call (methods take the key positional first). Only
/// the lifecycle contract is shared here.
abstract interface class BasicSplitClient {
  /// Resolves when the SDK has fetched its initial data and is ready to
  /// evaluate treatments (spec §8.1/§8.2). Returns immediately if already
  /// ready.
  Future<void> whenReady();

  /// Resolves if the SDK fails to become ready within the configured
  /// timeout. Never rejects.
  Future<void> whenTimeout();

  /// Emits the list of flag names that changed on each successful sync
  /// cycle after readiness. Closes (subscribers receive `onDone`) when this
  /// client is destroyed, or when its factory is destroyed (spec §8.2).
  Stream<List<String>> whenUpdated();

  /// Fires one final POST per recorder (best-effort, no retries). Safe to
  /// await from application code. MUST NOT throw.
  Future<void> flush();

  /// Marks the client destroyed. Subsequent evaluations return `control`;
  /// subsequent `track` returns `false`. MUST NOT throw. Idempotent.
  Future<void> destroy();
}
