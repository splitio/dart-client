# observer

Generic pub/sub primitive (dependency-free, no I/O). Decouples internal emitters (factory, sync, streaming, HTTP, auth, recorders) from consumers.

## Key exports

| Type | Description |
|---|---|
| `Observer` | Consumer callback interface for observing events |
| `ObserverRegistry` | Central registry for managing observers |
| `CompositeObserver` | Multiplexer combining multiple observers |
| `ObservableEvent` | Event wrapper for pub/sub messaging |

## Dependencies

**Internal:** none  
**External:** none

## Spec reference

SDK Specification v1 §3.1 — Shared core (observer primitive)
