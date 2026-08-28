# AGENTS.md — event_tracker

## Purpose

**Custom event tracking pipeline** — Validates, batches, and flushes user-generated `track()` events to the Split backend. Owns the in-memory events store and the flush/recorder cycle. Maps to spec §5.

## Key Files

- `event_tracker.dart` — Library export
- `events_tracker.dart` — `EventsTracker` orchestrator (validate → store → flush)
- `event.dart` — `Event` value type
- `event_validator.dart` — Input validation (traffic type, event type, value bounds)
- `events_store.dart` — In-memory bounded queue

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/event_tracker/`
- **Focus**: Validation rules, queue bounds, flush triggering, recorder interaction

## Dependencies

- **Internal**: `models`, `storage`
- **External**: None
- **Used by**: `splitio_client_side` (via `SplitClient.track`)

## DOs

- Validate all inputs at the boundary; drop invalid events with a log warning
- Respect queue size limits; drop oldest when full (spec §5)
- Keep the store in-memory only; no I/O in this layer

## DON'Ts

- Don't throw on invalid events — validate and drop
- Don't perform HTTP here; delegate to the recorder/sync layer
