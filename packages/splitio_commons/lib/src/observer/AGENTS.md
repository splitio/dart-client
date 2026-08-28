# AGENTS.md — observer

## Purpose

**Generic pub/sub primitive** — Zero dependencies, no I/O. Decouples internal emitters from consumers for SDK lifecycle events (ready, update, error, etc.).

## Key Files

- `observer.dart` — `Observer` abstract interface (`notifyEvent`)
- `observer_registry.dart` — `ObserverRegistry` abstract interface (register/unregister/unregisterAll)
- `observable_event.dart` — Immutable value object (type, properties, payload, timestamp)
- `composite_observer.dart` — `CompositeObserver`: implements both interfaces; snapshot dispatch + fault isolation

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/observer/`
- **Focus**: Snapshot dispatch, fault isolation (one bad observer doesn't block others), idempotent registration

## Dependencies

- **Internal**: None (zero dependencies — leaf)
- **External**: None

## Important Patterns

- **Snapshot dispatch**: `CompositeObserver.notifyEvent` iterates a copy of the list — safe against concurrent register/unregister
- **Fault isolation**: An exception in one observer is swallowed; remaining observers still receive the event
- **Emitters depend only on `Observer`**: Pass `CompositeObserver` as the `Observer` sink; emitters never see the registry

## DOs

- Keep this completely dependency-free
- Pass only immutable objects as `ObservableEvent.payload`

## DON'Ts

- Don't add any dependencies — must remain a universal leaf
- Don't expose Dart `Stream` directly
