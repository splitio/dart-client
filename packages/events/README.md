# events

Readiness/lifecycle manager for the Split SDK. Topologically orders internal milestones and latches public lifecycle events (`READY`, `READY_TIMEOUT`, `UPDATE`).

## Key exports

| Type | Description |
|---|---|
| `EventsManager` | Tracks internal milestones, emits latched lifecycle events |
| `SplitInternalEvent` | Internal milestone signals fed into the manager |

## Dependencies

**Internal:** `models` (public `SplitEvent`), `observer` (pub/sub) · **External:** none

## Spec reference

SDK Specification v1 — §3.1 (`events` module), §8 (Lifecycle & Readiness), §4.6 (lifecycle event).
