# AGENTS.md — impressions

## Purpose

**Impression recording pipeline** — Captures `getTreatment` impressions and routes them through a pluggable strategy (debug / optimized / none). Owns the in-memory store, dedup observer, counter, and the flush/recorder cycle. Maps to spec §4.5 and §13.

## Key Files

- `impressions.dart` — Library export
- `impressions_manager.dart` — `ImpressionsManager`: strategy selection + flush orchestration
- `impression_strategy.dart` — `ImpressionStrategy` SPI (debug, optimized, none)
- `impressions_counter.dart` — Optimized-mode MTK counter
- `impressions_observer.dart` — Dedup observer (last-seen cache)

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/impressions/`
- **Focus**: Strategy selection per config, dedup correctness, counter behavior, flush triggering

## Dependencies

- **Internal**: `models`, `storage`
- **External**: None
- **Used by**: `splitio_client_side` (called after each evaluation)

## Important Patterns

- **Strategy pattern**: behavior (what to store, whether to dedup) is determined by the injected `ImpressionStrategy`
- **Optimized mode**: stores only first impression per MTK per interval; counter tracks the rest

## DOs

- Select strategy at construction time based on `impressionsMode` config
- Keep the store in-memory; no I/O in this layer

## DON'Ts

- Don't perform HTTP here — delegate to the recorder/sync layer
- Don't mix strategy logic into the manager; keep strategies self-contained
