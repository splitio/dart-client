# AGENTS.md — sync

## Purpose

**Inbound freshness coordinator** — Keeps local stores current with the Split backend via polling and SSE streaming. Implements one flavor-agnostic `SyncManager` (sync-mode switch) with a per-flavor `PollingManager` strategy, cursor-aware fetchers, and the full streaming stack: pure FSM (`StreamingPolicy`) separated from its effect runtime (`StreamingManager`). Maps to spec §10–§12.

## Key Files

- `sync.dart` — Library export
- `sync_manager.dart` — Flavor-agnostic poll/stream orchestrator + sync-mode switch; decides *when* to poll, the injected `PollingManager` decides *what*
- `polling/polling_manager.dart` — `PollingManager` strategy interface (`syncAll`, `start`, `stop`, `isRunning`)
- `polling/polling_manager_cs.dart` — CS: flags + per-key memberships (`syncMembershipsFor`)
- `polling/polling_manager_ss.dart` — SS: flags, then segments via the injected `fetchSegments` (`/segmentChanges` per referenced segment); segments are fetched even when flags fail
- `compression/notification_payload_decoder.dart` — base64 + `c` → decoded `d` (only place that decodes)
- `compression/inflate_decompressor.dart` — pure-Dart gzip/zlib `Decompressor` (fflate port, MIT)
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
- **Used by**: `splitio_client_side`, `splitio_server_side`

## Important Patterns

- **FSM separation**: `StreamingPolicy` is a pure zero-I/O reducer; all mechanism is in `StreamingManager`
- **Injected time**: reconnect backoff + jitter go through `Scheduler`/`Clock` SPI for deterministic tests
- **3-axis push gate**: `pushUp = !controlPaused && !occupancyZero && !connectionDown`
- **Safe fallback**: any decode error or unknown `c` → full fetch, never throw; a decode error on a non-empty `d` logs one WARNING per notification
- **Compression**: `NotificationPayloadDecoder` (base64 → `Decompressor`, pure-Dart gzip/zlib in `compression/`) decodes `c`=0/1/2 for SPLIT_UPDATE, BOUNDED and KEY_LIST; `RB_SEGMENT_UPDATE` still always fetches
- **No `BigInt`** (web compat): key-list hashes compared as decimal strings; bitmap uses low 32 bits

## DOs

- Keep `StreamingPolicy` pure (no I/O, no timers, no async)
- Route platform I/O through injected `StreamingTransport` and `Scheduler`/`Clock`
- Handle change-number/pcn correctly for in-place applies; fall back to fetch when unsure

## DON'Ts

- Don't make direct HTTP calls — use injected transport/fetchers
- Don't use `BigInt` or `dart:io`/`dart:html`
- Don't decode `d` anywhere but `NotificationPayloadDecoder`; don't apply `RB_SEGMENT_UPDATE` in place (always fetch)
