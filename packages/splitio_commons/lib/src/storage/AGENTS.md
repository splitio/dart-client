# AGENTS.md — storage

## Purpose

**Generic change-based stores + persistence seam** — `Store<T>` interface, in-memory stores with atomic change-number tracking, and the `PersistentStore` SPI (no-op in v1). Maps to spec §3.1 `storage-core`; consistency rules in §9.

## Key Files

- `storage.dart` — Library export
- `store.dart` — `Store<T>` interface
- `persistent_store.dart` — `PersistentStore` SPI (no-op v1)
- `rule_store.dart` — In-memory flag/split store
- `rule_based_segment_store.dart` — In-memory RBS store
- `membership_store.dart` — In-memory membership store
- `impressions_store.dart` — In-memory impressions queue

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/storage/`
- **Focus**: Atomic change-number + data updates (§9), change-based merges, no-op persistence

## Dependencies

- **Internal**: `models`
- **External**: None
- **Used by**: `local`, `sync`, `impressions`, `event_tracker`

## Important Patterns

- **Atomic updates**: Change-number and data MUST update together — no torn reads (§9)
- **`PersistentStore` SPI**: Declared port; v1 default is no-op

## DOs

- Guarantee atomic data + change-number swaps
- Keep stores pure (no disk/network I/O in the in-memory impl)

## DON'Ts

- Don't expose mutable internal collections to readers
- Don't add dependencies beyond `models`
