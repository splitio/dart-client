# AGENTS.md — splitio_server_side package

## Purpose

**Public SDK entry point, server-side flavor** — One factory, one `ServerSplitClient` that takes the key on every call. Syncs flags via `/splitChanges` and segments via `/segmentChanges/{name}` (streaming via SSE with polling fallback), and flushes on SIGTERM/SIGINT. Targets the **Dart VM only** — uses `dart:io` directly.

## Key Files

- `lib/splitio_server_side.dart` — Public library export
- `lib/src/internal/split_factory.dart` — `SplitFactory`: startup, readyTimeout, destroy
- `lib/src/internal/dependency_container.dart` — `ServerDependencyContainer` DI root (LOC-exemption: approved 2026-09-22)
- the shared commons `SyncManager` (with `PollingManagerSS`) — initial sync, polling timers, streaming push up/down edges, recorders
- `lib/src/internal/flags_segment_sync.dart` — `FlagsSegmentSync`: re-registers referenced segments after every flags change and fetches a never-fetched segment immediately
- `lib/src/internal/referenced_segments.dart` — collects segment names referenced by flags (drives `/segmentChanges` registration)
- `lib/src/internal/split_manager.dart` — server `SplitManager` over the shared `SplitManagerImpl`
- `lib/src/internal/signal_listener.dart` — SIGTERM/SIGINT → `factory.destroy()` → `exit`
- `lib/src/client/split_client.dart` — `ServerSplitClient` (+ NoOp client returned for an empty SDK key). `SplitClientImpl` is a thin adapter: it maps the `Object` key to a `Key` (`_asKey`) and delegates to the commons `TreatmentMethods` / `TrackMethod`, implementing `ClientState`

## Testing

- **Run tests**: `cd packages/splitio_server_side && dart test`
- **Integration tests**: `packages/e2e/test/server_side_*_e2e_test.dart` (lifecycle, input validation, bucketing key, streaming segment catch-up)
- `SignalListener` takes injected signal streams and `exitFn` — unit tests never send real signals

## Dependencies

- **Internal**: `splitio_commons` only (reuses `SplitManagerImpl`, `UserConsentManager`, the client core in `lib/src/client/`, and `SyncManager` from it). Must not depend on `splitio_client_side`
- **External**: None

## Important Patterns

- Mirrors `splitio_client_side` layout on purpose — same directory names and wiring style
- Reference implementation for behavior questions: `javascript-commons` (server-side paths) + `javascript-client` (Node)
- See root `AGENTS.md` → **Factory Lifecycle Rules** (timers, startup error handling, signal watchers)

## DON'Ts

- Don't import this package's `dart:io` usage patterns into `splitio_commons` or `splitio_client_side`
- Don't leave `ProcessSignal.watch()` subscriptions alive after `dispose()` — they block the signal's default action
