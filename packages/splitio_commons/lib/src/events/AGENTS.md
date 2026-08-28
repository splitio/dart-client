# AGENTS.md — events

## Purpose

**Readiness/lifecycle manager** — Topologically orders internal milestones and emits the single ordered, milestone-latched public lifecycle stream (`READY`, `READY_TIMEOUT`, `UPDATE` with changed flag names). Maps to spec §8 and §4.6.

## Key Files

- `events.dart` — Library export
- `events_manager.dart` — `EventsManager`: milestone tracking, latch semantics, public event emission

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/events/`
- **Focus**: Latching (late subscribers still receive `READY`), ordering, timeout path, `UPDATE` payloads

## Dependencies

- **Internal**: `models`, `observer`
- **External**: None
- **Used by**: `splitio_client_side` (readiness wiring)

## Important Patterns

- **Latched milestones**: Once a milestone fires it stays fired; late listeners replay it immediately
- **Topological ordering**: Internal events resolve into public events in a fixed order (§8.2)

## DOs

- Preserve latch semantics — readiness must be observable after the fact
- Emit `UPDATE` with the changed flag-name set per §8

## DON'Ts

- Don't perform sync/network work here — only react to internal events
- Don't add dependencies beyond `models` and `observer`
