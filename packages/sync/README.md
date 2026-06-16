# sync

Inbound freshness coordinator—manages SyncManager, FeedSynchronizer, streaming FSM, on-demand fetch coordinator, and sync delays. Pure FSM (StreamingPolicy) separated from effect runtime. Coordinates rules + memberships convergence.

## Key exports

| Type | Description |
|---|---|
| `SyncManager` | Orchestrates polling and streaming synchronization of feeds |
| `FeedSynchronizer` | Handles individual feed syncs with change-number tracking |
| `StreamingManager` | Drives streaming transport with reconnect/backoff logic |
| `StreamingPolicy` | Pure FSM (reduce-based) for streaming state transitions |
| `OnDemandFetchCoordinator` | Coordinates on-demand fetches with CDN bypass (toggleable) |
| `SyncDelayCalculator` | Applies seed-based jitter delay for load spreading |

## Dependencies

**Internal:** models, storage, parsing, auth (path refs)  
**External:** none

## Spec reference

SDK Specification v1 §3.1 — Shared runtime; §10 — Synchronization Protocol (Poll Path); §11 — Streaming State Machine; §12 — Notification Update Strategies
