# AGENTS.md — observer package

## Purpose

**Generic pub/sub primitive** — Dependency-free, no I/O. Decouples internal emitters (factory, sync, streaming, HTTP, auth, recorders) from consumers. Used for internal SDK event notification (ready, update, error, etc.) without coupling emitters to consumers.

## Key Files

- `lib/observer.dart` — Barrel export (all four public types)
- `lib/src/observable_event.dart` — Immutable value object (type, properties, payload, timestamp)
- `lib/src/observer.dart` — `Observer` abstract interface (`notifyEvent`)
- `lib/src/observer_registry.dart` — `ObserverRegistry` abstract interface (register/unregister/unregisterAll)
- `lib/src/composite_observer.dart` — `CompositeObserver` — implements both interfaces; snapshot dispatch + fault isolation
- `pubspec.yaml` — Zero dependencies (truly standalone)

## Testing

- **Run tests**: `cd packages/observer && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Pub/sub correctness, multiple listeners, unsubscribe behavior

## Dependencies

- **Internal**: None (zero dependencies — this is a leaf)
- **External**: None
- **Used by**: All packages that emit or consume internal SDK events

## Important Patterns

- **Zero dependencies**: Can be used by any package without introducing cycles
- **Emitters depend only on `Observer`**: Pass `CompositeObserver` as the `Observer` sink; emitters never see the registry
- **Snapshot dispatch**: `CompositeObserver.notifyEvent` iterates a copy of the observer list — safe against register/unregister during dispatch
- **Fault isolation**: An exception in one observer is swallowed; remaining observers still receive the event
- **Idempotent registration**: Registering the same observer instance twice is a no-op
- **Payload immutability**: `ObservableEvent.payload` must be an immutable value — mutating it from within an observer corrupts dispatch for subsequent observers

## DOs

- Keep this package completely dependency-free
- Use `CompositeObserver` as the concrete implementation in all wiring
- Pass only immutable objects as `ObservableEvent.payload`

## DON'Ts

- Don't add any dependencies — this must remain a universal leaf
- Don't add async complexity beyond Dart's standard async model
- Don't expose Dart's `Stream` directly — abstract it for testability
