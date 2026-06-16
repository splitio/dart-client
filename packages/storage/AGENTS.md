# AGENTS.md — storage package

## Purpose

**Generic change-based store + in-memory impl + persistence seam** — `Store<T>` interface, in-memory stores, change-number tracking, and the `PersistentStore` SPI (no-op in v1). Pure data structure, no I/O. Maps to spec §3.1 `storage-core`; consistency rules in §9.

## Key Files

- `lib/storage.dart` — Library export
- `lib/src/store.dart` — `Store<T>` interface (to be created)
- `lib/src/persistent_store.dart` — `PersistentStore` SPI (no-op v1) (to be created)
- `lib/src/rule_store.dart`, `lib/src/rule_based_segment_store.dart` — flag/rbs stores (to be created)
- `pubspec.yaml` — Depends on `models` only

## Testing

- **Run tests**: `cd packages/storage && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Atomic change-number + data updates (§9), change-based merges, no-op persistence

## Dependencies

- **Internal**: `models`
- **External**: None
- **Used by**: `local`, `client`, `sync`, `sdk_internal`

## Important Patterns

- **Atomic updates**: Change-number and data MUST update together — no torn reads (§9)
- **Change-based**: Apply deltas keyed by change number; ignore stale updates
- **`PersistentStore` SPI**: Declared port; v1 default is no-op (`loadLocal()` always called)

## DOs

- Keep stores pure (no network/disk I/O in the in-memory impl)
- Guarantee atomic data + change-number swaps for lock-free reads
- Keep the `PersistentStore` seam present even though v1 is no-op

## DON'Ts

- Don't perform I/O in the in-memory store
- Don't expose mutable internal collections to readers
- Don't add dependencies beyond `models`
