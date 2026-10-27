/// The "keep segments fresh" seam.
///
/// Client-side implementations poll `/memberships/{key}` per bound user
/// key. Server-side implementations will poll `/segmentChanges/{name}` per
/// segment referenced by the current rule set. Both are periodically
/// invoked by the polling manager; both return whether the cycle succeeded so
/// polling backoff and readiness can react.
///
/// Kept deliberately narrow — no `bindKey`, no `boundKeys`, no per-key
/// state on the interface — because those concepts are CS-specific.
abstract interface class SegmentSyncTask {
  /// Perform one refresh cycle. Returns true on success, false on any
  /// failure. Implementations MUST NOT throw — callers rely on the boolean
  /// to drive readiness and backoff.
  Future<bool> fetch();
}
