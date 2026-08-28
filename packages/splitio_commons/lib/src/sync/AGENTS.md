# AGENTS.md — sync

## Purpose

**Inbound freshness coordinator** — Keeps local stores current with the Split backend via polling and SSE streaming. Implements `SyncManager` (sync-mode switch), cursor-aware fetchers, and the full streaming stack: pure FSM (`StreamingPolicy`) separated from its effect runtime (`StreamingManager`). Maps to spec §10–§12.

## Key Files

- `sync.dart` — Library export
- `sync_manager.dart` — Poll/stream orchestrator + sync-mode switch
- `task.dart` — Periodic task abstraction
- `fetchers/flags_fetcher.dart` — Cursor-aware flags fetch (§10)
- `fetchers/memberships_fetcher.dart` — Cursor-aware memberships fetch (§10)
- `recorders/impressions_recorder.dart` — Flushes impressions to backend
- `recorders/events_recorder.dart` — Flushes track events to backend
- `recorders/telemetry_recorder.dart` — Reserved seam (§17.2): `flush()` is a no-op in v1, not wired into `DependencyContainer`; declared so a future impl can land without core surgery
- `streaming/streaming_policy.dart` — Pure FSM `reduce(state, event) → (state, effects)` (§11.1-11.3)
- `streaming/streaming_manager.dart` — Effect runtime (socket, reconnect/backoff, token, routing)
- `streaming/event_source_client.dart` — SSE framing + Ably envelope double-decode (§11.0)
- `streaming/notification_processor.dart` — Categorizer → `FeedUpdate` or FSM event (§11.4)
- `streaming/flag_update_strategy.dart` — SPLIT_UPDATE / SPLIT_KILL (§12.1)
- `streaming/membership_update_strategy.dart` — 4 membership strategies (§12.2)
- `streaming/membership_payload_decoder.dart` — Hashing/bitmap/key-list (§12.3, no BigInt)
- `streaming/streaming_state.dart` / `streaming_event.dart` / `streaming_effect.dart` — FSM vocabulary
- `streaming/clock.dart` — `Clock`/`Scheduler` SPI + real impls
- `streaming/sync_delay_calculator.dart` — Seed-based jitter (§12.3)
- `streaming/sse_uri_builder.dart` — SSE endpoint URL construction

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/sync/`
- **Streaming tests**: `dart test test/sync/streaming/`
- **Focus**: Exhaustive FSM state×event transitions, SSE framing edge cases, §12 strategy handling, key-list decimal-string compare, jitter, reconnect/backoff/fallback with `FakeStreamingTransport` + `FakeScheduler`/`FakeClock`

## Dependencies

- **Internal**: `models`, `logger`, `storage`, `parsing`, `auth`, `http_client`
- **External**: None
- **Used by**: `splitio_client_side`

## Important Patterns

- **FSM separation**: `StreamingPolicy` is a pure zero-I/O reducer; all mechanism is in `StreamingManager`
- **Injected time**: reconnect backoff + jitter go through `Scheduler`/`Clock` SPI for deterministic tests
- **3-axis push gate**: `pushUp = !controlPaused && !occupancyZero && !connectionDown`
- **Safe fallback**: any decode error or deferred compression (`c=1/2`) → full fetch, never throw
- **No `BigInt`** (web compat): key-list hashes compared as decimal strings; bitmap uses low 32 bits

## DOs

- Keep `StreamingPolicy` pure (no I/O, no timers, no async)
- Route platform I/O through injected `StreamingTransport` and `Scheduler`/`Clock`
- Handle change-number/pcn correctly for in-place applies; fall back to fetch when unsure

## DON'Ts

- Don't make direct HTTP calls — use injected transport/fetchers
- Don't use `BigInt` or `dart:io`/`dart:html`
- Don't apply compressed (`c=1/2`) payloads in place — fetch instead
