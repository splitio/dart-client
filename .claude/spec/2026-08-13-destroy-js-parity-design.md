# Design: `destroy` parity with JS SDK

**Date:** 2026-08-13
**Status:** Approved for implementation planning
**Related spec section:** `docs/SDK-Specification-v1-RFC2119.md` §7 (SplitClient / SplitFactory)

## Problem

Dart `SplitClientImpl.destroy()` is an empty stub at
`packages/splitio_client_side/lib/src/client/split_client.dart:234`. After
`factory.destroy()`, a client that keeps a reference to a `SplitClient`
instance can still call `track` / `getTreatment*` — the calls do not fail
fast and the guard around `EventsManager.isDestroyed` at
`split_client.dart:170-175` conflates factory teardown with per-client
destroy, so it cannot express shared-client destroy either.

The JS SDK gates per client, distinguishes main vs shared destroy, and
guarantees ordering: mark destroyed → stop timers → flush → dispose. The
Dart SDK must match this behavior.

## Goals

1. Per-client `_destroyed` flag on `SplitClientImpl` gating `track`,
   `getTreatment*`, and `flush`.
2. `factory.destroy()` == destroying the main client == full factory
   teardown.
3. `client.destroy()` on a shared client marks only that client destroyed;
   the factory keeps running so other shared clients keep working.
4. Destroy ordering (main path): mark destroyed → stop timers/streaming →
   stop recorder timers → flush recorders → dispose HTTP / JWT / events
   manager.
5. `SyncManager.stopRecorders()` split into stop-only + reuse existing
   `flushRecorders()` so the caller controls order.
6. Doc note on `SplitClient.destroy()` telling shared-client users to call
   `flush()` first if they need queued data sent immediately.

## Non-Goals

- `releaseApiKey` factory registry (JS prevents duplicate factories per
  SDK key). Out of scope; ship as a follow-up.
- `telemetryTracker.sessionLength()`. Out of scope.
- `flush()` cooldown. Out of scope.
- The backend-side properties visibility issue that surfaced during
  investigation — confirmed to be downstream of the SDK.

## Behavioral Contract

### `SplitClientImpl.destroy()`

- Idempotent: repeated calls are safe no-ops.
- Sets `_destroyed = true`.
- If this is the **main** client → delegates to the factory's teardown
  closure (`_onMainDestroy`), producing full teardown.
- If this is a **shared** client → returns immediately after marking
  destroyed. No flush, no stop, no dispose. Queued data for this key
  stays in the factory-wide queues and rides the next periodic push (or
  the main-client destroy).

### `SplitFactory.destroy()` (main teardown)

Steps, in order:

1. Mark the main `SplitClientImpl` destroyed.
2. Mark every issued shared `SplitClientImpl` destroyed (rejects late
   calls on cached shared client references).
3. `syncManager.stop()` — cancels poll timers, stops streaming.
4. `syncManager.stopRecorders()` — stops recorder timers (no flush).
5. `syncManager.flushRecorders()` — one final POST for impressions and
   events.
6. Dispose: clear JWT cache, close HTTP client, dispose
   `EventsManager`.
7. Idempotent: second call is a no-op.

`SplitFactory.destroy()` and `factory.client().destroy()` on the main
client produce identical teardown — the public factory method is
shorthand for destroying the main client.

### Guards after destroy (that client only)

| Method | Behavior after destroy |
|--------|-----------------------|
| `track(...)` | logs `"track: Client has already been destroyed - no calls possible"`, returns `false`, does not queue |
| `getTreatment(...)` | returns `'control'` |
| `getTreatments(...)` / `*ByFlagSets` | list of `'control'` |
| `getTreatmentWithConfig(...)` / `*WithConfig` / `*WithConfigByFlagSets` | `EvaluationResult(treatment: 'control')` / list of same |
| `flush()` | returns `Future.value()`, does not call `syncManager.flushRecorders` |
| `whenReady()` / `whenTimeout()` / `whenUpdated()` | still readable (JS keeps status readable after destroy) |

Other shared clients issued by the same factory remain fully functional
until they themselves are destroyed or the main client is destroyed.

## Code-level Changes

### `packages/splitio_client_side/lib/src/client/split_client.dart`

- Add `bool _destroyed = false` to `SplitClientImpl`.
- Add `bool _isMain` and `Future<void> Function() _onMainDestroy`
  constructor params. Default `_isMain: false`,
  `_onMainDestroy: () async {}`.
- `destroy()`: if `_destroyed` → return; set `_destroyed = true`; if
  `_isMain` → `await _onMainDestroy()`.
- Add `if (_destroyed)` guard at the top of `track`, `getTreatment`,
  `getTreatments`, `getTreatmentsByFlagSets`, `getTreatmentWithConfig`,
  `getTreatmentsWithConfig`, `getTreatmentsWithConfigByFlagSets`,
  `flush`. Log + return the destroyed fallback (`false`, `'control'`,
  `[]`, `Future.value()`).
- Doc comment on the abstract `SplitClient.destroy()` method:
  > For shared clients, only this client is marked destroyed; queued
  > data rides the next periodic push. Call `flush()` first to send
  > queued data immediately.

### `packages/splitio_client_side/lib/src/internal/split_factory.dart`

- Track all issued clients: `final List<SplitClientImpl> _issuedClients = []`.
- `_createClient` appends to `_issuedClients` and passes
  `isMain: identical(key, _key)` plus a captured `_onMainDestroy`
  closure that calls `_destroyAll()`.
- New private `Future<void> _destroyAll()`:
  1. Guard with `bool _factoryDestroyed` (idempotent).
  2. Mark every entry in `_issuedClients` destroyed.
  3. `di.syncManager.stop()`.
  4. `di.syncManager.stopRecorders()`.
  5. `di.syncManager.flushRecorders()`.
  6. `di.dispose()` for HTTP / JWT / events-manager cleanup.
- Public `SplitFactory.destroy()` → `_defaultClient.destroy()` (routes
  through `_onMainDestroy` closure) — single teardown path.
- `_NoOpSplitFactory.destroy` / `_NoOpSplitClient.destroy` remain
  no-op.

### `packages/splitio_commons/lib/src/sync/sync_manager.dart`

- Split `stopRecorders()` (currently `flush() then stop()` per
  recorder) into:
  - `stopRecorders()` → only calls `recorder.stop()` on each.
  - `flushRecorders()` → already exists, unchanged.
- Existing caller (`DependencyContainer.dispose`) updated to call
  both explicitly.

### `packages/splitio_commons/lib/src/events/events_manager.dart`

- No change required. `isDestroyed` there is no longer consulted by the
  client (per-client state moved to `SplitClientImpl`); left in place
  because `dispose()` still needs it.

### `packages/splitio_client_side/lib/src/internal/dependency_container.dart`

- `dispose()` no longer implicitly flushes. The factory teardown owns
  ordering; `dispose` handles cleanup only: `syncManager.stop()`
  (already there), `_authProvider?.clearAll()`, `httpClient.close()`,
  `eventsManager.dispose()`.

## Development Flow (Tidy First, TDD)

Per `AGENTS.md` §Development Flow.

1. **Tidy (structural, no behavior change):** Split
   `SyncManager.stopRecorders()`. Update the one existing caller so
   the observable end-state is preserved. Update sync-manager unit
   tests.
2. **Tidy (structural):** Add `_destroyed`, `_isMain`,
   `_onMainDestroy` fields on `SplitClientImpl` with harmless
   defaults. Factory wires them per client. Behavior unchanged.
3. **RED — e2e:** Add shared-client-track-after-destroy and shared-
   client-flush-on-destroy tests in
   `packages/e2e/test/events_e2e_test.dart`; add ordering assertion
   (no polls after destroy) in the readiness/lifecycle e2e. Commit
   alone — fails.
4. **RED — unit:** Add
   `packages/splitio_client_side/test/client/split_client_impl_destroy_test.dart`
   and new cases in
   `packages/splitio_client_side/test/internal/split_factory_test.dart`.
   Commit alone — fails.
5. **GREEN — behavior:** Guards at the top of every affected client
   method; `SplitClientImpl.destroy()` implementation; factory
   `_destroyAll` wiring; `DependencyContainer.dispose` cleanup-only.
   Route `SplitFactory.destroy` through `_defaultClient.destroy`.
6. **REFACTOR (only if needed):** Consolidate destroyed-fallback
   returns behind a small helper if guard blocks become repetitive.
   Skip if clean.
7. **Spec sync:** Update `docs/SDK-Specification-v1-RFC2119.md` §7 via
   the `update-spec` skill — main vs shared destroy, ordering,
   idempotency, guards. Lands together with the code (or in commit 5
   if minor).

Every commit passes `melos test` and `melos analyze`.

## Testing

### Unit tests

`packages/splitio_client_side/test/client/split_client_impl_destroy_test.dart` (new)

- `track` after `destroy` → returns `false`, logs error, event not
  queued.
- `getTreatment` after `destroy` → `'control'`.
- `getTreatments` / `*ByFlagSets` / `*WithConfig` after `destroy` → all
  `'control'` results.
- `flush` after `destroy` → completes, does not call
  `syncManager.flushRecorders`.
- `destroy` called twice on same client → second call is a no-op
  (spy on the main-destroy callback).
- Shared client `destroy` does not trigger `_onMainDestroy`.

`packages/splitio_client_side/test/internal/split_factory_test.dart`
(extend)

- `factory.destroy()` and `factory.client().destroy()` produce
  identical teardown (same spy calls, same order).
- After `factory.destroy()`, calling `track` on a previously-issued
  shared client returns `false`.
- Shared-client `destroy()` does not stop timers, does not flush
  recorders (spy on `SyncManager`), and other shared clients keep
  working.
- `factory.destroy()` is idempotent — second call performs no teardown
  work.

`packages/splitio_commons/test/sync/sync_manager_test.dart` (extend)

- `stopRecorders()` calls `stop()` on each recorder and does not call
  `flush()`.
- `flushRecorders()` remains unchanged (already covered).

### e2e tests

`packages/e2e/test/events_e2e_test.dart` (extend)

- `track` on a shared client after `factory.destroy()` → `false`, no
  bulk POST.
- `track` before `factory.destroy()` on a shared client → event
  flushed on destroy (verifies factory teardown flushes shared-client
  events too, since queues are factory-wide).

`packages/e2e/test/readiness_lifecycle_e2e_test.dart` (extend or new
file)

- Ordering: destroy stops poll/streaming before the final POSTs — no
  `/splitChanges` requests fire after `destroy()` completes; exactly
  one final `/events/bulk` and one `/testImpressions` POST after
  destroy.

### Manual verification

- Repro the pre-fix scenario (destroy after `track`) against a live
  Split tail; confirm events still flush post-change.

## Open Questions

None.

## Risks & Mitigations

- **Splitting `stopRecorders()` changes ordering semantics.** Existing
  caller (`DependencyContainer.dispose`) updated in the same tidy
  commit to preserve observable end-state. Unit test asserts the new
  contract of each method.
- **Shared-client destroy leaves data in shared queues.** This matches
  JS. The doc note on `destroy()` makes the expected pattern explicit
  ("call `flush()` first").
- **Idempotency bugs.** Covered by dedicated "second call is a no-op"
  unit test on both `SplitClientImpl.destroy` and factory teardown.
