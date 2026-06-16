# AGENTS.md — recorders package

## Purpose

**Impression and event pipeline** — Implements recorders for impressions, events, unique-keys, and impression-counts. Generic queue → batch → flush pipeline. Handles deduplication and observer patterns for impressions. Buffers data locally and flushes to the Split backend on a schedule or trigger.

## Key Files

- `lib/recorders.dart` — Library export
- `lib/src/impression_recorder.dart` — Impression queue + dedup + flush (to be created)
- `lib/src/event_recorder.dart` — Event queue + batch + flush (to be created)
- `lib/src/unique_keys_recorder.dart` — Unique-key tracking (to be created)
- `pubspec.yaml` — Depends on `models`

## Testing

- **Run tests**: `cd packages/recorders && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Deduplication logic, batching behavior, flush triggers, queue overflow

## Dependencies

- **Internal**: `models`
- **External**: None (HTTP client injected by `sdk_internal`)
- **Used by**: `sdk_internal` (wired with HTTP client and flush schedule)

## Important Patterns

- **Generic pipeline**: `Queue<T>` → `Batcher<T>` → `Flusher<T>` — reuse across recorder types
- **Impression dedup**: Use observer pattern to deduplicate impressions within a time window
- **Flush triggers**: Time-based (periodic) and count-based (queue size threshold) triggers
- **Graceful overflow**: Drop oldest records if queue exceeds max capacity

## DOs

- Implement the generic pipeline so impression/event/unique-key recorders share it
- Test deduplication edge cases (same key, different timestamps)
- Test flush on count threshold and time interval
- Handle flush failures gracefully (retry or discard with logging)

## DON'Ts

- Don't make direct HTTP calls — receive HTTP client via injection
- Don't block the evaluation hot path — recording must be async/non-blocking
- Don't lose impressions silently — log or surface drops
