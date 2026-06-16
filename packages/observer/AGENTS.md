# AGENTS.md — observer package

## Purpose

**Generic pub/sub primitive** — Dependency-free, no I/O. Decouples internal emitters (factory, sync, streaming, HTTP, auth, recorders) from consumers. Used for internal SDK event notification (ready, update, error, etc.) without coupling emitters to consumers.

## Key Files

- `lib/observer.dart` — Library export
- `lib/src/event_producer.dart` — Publisher/emitter interface (to be created)
- `lib/src/event_consumer.dart` — Subscriber/listener interface (to be created)
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
- **Typed events**: Use generic types or an event enum for type-safe pub/sub
- **Synchronous delivery**: Events delivered synchronously in Dart's event loop
- **Unsubscribe support**: Listeners must be removable to avoid memory leaks

## DOs

- Keep this package completely dependency-free
- Support typed events so consumers don't need to cast
- Implement listener cleanup (return a subscription object or cancel function)
- Test for listener isolation (one failing listener shouldn't affect others)

## DON'Ts

- Don't add any dependencies — this must remain a universal leaf
- Don't add async complexity beyond Dart's standard async model
- Don't expose Dart's `Stream` directly — abstract it for testability
