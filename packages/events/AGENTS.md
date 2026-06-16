# AGENTS.md — events package

## Purpose

**Readiness/lifecycle manager** — Topologically orders internal milestones and emits the single ordered, **milestone-latched** public lifecycle stream (`READY`, `READY_TIMEOUT`, `UPDATE` with changed flag names). Maps to spec §3.1 `events`; behavior in §8 and §4.6.

## Key Files

- `lib/events.dart` — Library export
- `lib/src/events_manager.dart` — `EventsManager` (to be created)
- `lib/src/split_internal_event.dart` — `SplitInternalEvent` signals (to be created)
- `pubspec.yaml` — Depends on `models` and `observer`

## Testing

- **Run tests**: `cd packages/events && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Latching (late subscribers still receive `READY`), ordering, timeout path, `UPDATE` payloads

## Dependencies

- **Internal**: `models` (public `SplitEvent`), `observer` (pub/sub primitive)
- **External**: None
- **Used by**: `client`, `sdk_internal` (readiness wiring)

## Important Patterns

- **Latched milestones**: Once a milestone fires it stays fired; late listeners replay it
- **Topological ordering**: Internal events resolve into public events in a fixed order (§8.2)
- **No I/O**: Pure coordination over the observer bus

## DOs

- Preserve latch semantics — readiness must be observable after the fact
- Emit `UPDATE` with the changed flag-name set per §8
- Keep coordination logic free of network/storage access

## DON'Ts

- Don't perform sync/network work here — only react to internal events
- Don't expose Dart `Stream` internals; go through `observer`/`models` types
- Don't add dependencies beyond `models` and `observer`
