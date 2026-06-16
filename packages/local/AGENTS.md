# AGENTS.md — local package

## Purpose

**LOCAL-eval wiring (Axis 2 = LOCAL)** — Binds the pure `engine` to `storage` via `EvaluationContext`, implements the `Evaluator` port, and assembles result metadata. Also owns the LOCAL-specific rule store, network facade, and notification processor. Maps to spec §3.2.

## Hybrid sub-module layout

This package consolidates four spec §3.2 modules as directories under `lib/src/` (see `docs/SPEC-MODULE-MAP.md`):

| Spec §3.2 module | Path | Key contracts |
|---|---|---|
| `local-evaluator` | `lib/src/evaluator/` | implements `Evaluator`, `EvaluationContext` |
| `rules` | `lib/src/rules/` | `RuleStore`, `RuleBasedSegmentStore`, `RuleFeed`, flagSet index |
| `local-network` | `lib/src/network/` | `NetworkFacade` (canonical §10.4 query-param order) |
| `local-notifications` | `lib/src/notifications/` | `NotificationProcessor` → `FeedUpdate` |

## Testing

- **Run tests**: `cd packages/local && dart test`
- **Focus**: store lookup + recursive eval, segment dispatch, §10.4 query-param ordering, notification → `FeedUpdate`

## Dependencies

- **Internal**: `engine`, `storage`, `parsing`, `models`
- **External**: None
- **Used by**: `client`, `sdk_internal`

## Important Patterns

- **Metadata at the edge**: engine returns `{treatment,label}`; `local-evaluator` attaches config/changeNumber (§4.3)
- **Canonical query order**: `local-network` MUST emit `s`→`since`→`rbSince`→[`sets`]→[`till`] (§10.4)
- **Combined rules+rbs feed**: dual cursor, single fetch per cycle (§10.1)

## DOs

- Keep the engine pure — all store access flows through `EvaluationContext`
- Preserve `bucketingKey == null` until bucketing time (§4.1)
- Honor the canonical CDN query-param order

## DON'Ts

- Don't put matching logic here — that belongs in `engine`
- Don't let `getTreatment` do I/O or throw (§2.2)
- Don't add dependencies beyond engine/storage/parsing/models
