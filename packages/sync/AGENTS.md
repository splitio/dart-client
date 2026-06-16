# AGENTS.md — sync package

## Purpose

**Inbound freshness coordinator** — Manages keeping the local stores up to date with the Split backend. Implements `SyncManager`, `FeedSynchronizer`, streaming FSM (`StreamingPolicy`), on-demand fetch coordinator, and sync delays. Pure FSM logic is separated from the effect runtime. Coordinates convergence of both rules (splits) and memberships (segments).

## Key Files

- `lib/sync.dart` — Library export
- `lib/src/sync_manager.dart` — Top-level sync orchestrator (to be created)
- `lib/src/streaming/` — SSE streaming FSM and event handling (to be created)
- `lib/src/polling/` — Polling fallback implementation (to be created)
- `pubspec.yaml` — Depends on `models`, `storage`, `parsing`, `auth`

## Testing

- **Run tests**: `cd packages/sync && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: FSM state transitions, retry/backoff logic, convergence behavior

## Dependencies

- **Internal**: `models`, `storage` (writes updates), `parsing` (deserializes responses), `auth` (credentials for requests)
- **External**: None (`http_client` is wired in by `sdk_internal`, not a direct dep)
- **Used by**: `sdk_internal` (wiring root)

## Important Patterns

- **FSM separation**: `StreamingPolicy` is pure state machine; runtime effects are separate
- **Dual sync**: Coordinates both splits (rules) and segments (memberships) separately
- **Fallback**: Streams → polling fallback on disconnect/error
- **Backoff**: Exponential backoff on failures with configurable delays
- **On-demand fetch**: Can trigger immediate sync on client `ready` events

## DOs

- Keep `StreamingPolicy` pure (no I/O) so it can be unit tested in isolation
- Handle partial updates (change-number based) correctly
- Coordinate splits and segments in the right order to avoid inconsistent state

## DON'Ts

- Don't make direct HTTP calls — receive an HTTP client via injection from `sdk_internal`
- Don't write to storage outside the designated sync paths
- Don't swallow errors silently — propagate via `observer` events
