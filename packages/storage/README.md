# storage

In-memory stores and the `Store<T>` interface. Change-based updates, change-number tracking.

## Key exports

| Type | Description |
|---|---|
| `Store<T>` | Generic change-based store interface; advances change-number and data atomically (§9) |
| `RuleStore` | Stores `ParsedSplit` (feature flags) indexed by name |
| `MembershipStore` | Stores per-Key standard (MS) and large (LS) segment memberships |
| `RuleBasedSegmentStore` | Stores global rule-based segments |
| `PersistentStore` | SPI for durable persistence; v1 no-op implementation |

## Scope

This package covers **inbound evaluation data only** — rules, memberships, and segments synced from the backend. It does not handle outbound telemetry.

Outbound queuing (impressions, events, impression-counts, unique-keys) lives in `recorders`, which uses its own append/drain queue model — not `Store<T>`.

## Dependencies

**Internal:** models (path ref)  
**External:** none

## Spec reference

SDK Specification v1 §3.1 (Shared core), §6 (Port & SPI Contracts)
