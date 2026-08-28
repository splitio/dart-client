# AGENTS.md — local

## Purpose

**LOCAL-eval wiring** — Binds the pure `engine` to `storage` via `EvaluationContext`, implements the `Evaluator` port, and assembles result metadata. Also owns the local rule store, network facade, and notification processor. Maps to spec §3.2.

## Key Files

- `local.dart` — Library export
- `local_evaluator.dart` — `LocalEvaluator`: implements `Evaluator`, bridges engine + storage

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/local/`
- **Focus**: Store lookup + recursive segment eval, §10.4 query-param ordering, metadata attachment

## Dependencies

- **Internal**: `engine`, `storage`, `parsing`, `models`, `core`
- **External**: None
- **Used by**: `splitio_client_side`

## Important Patterns

- **Metadata at the edge**: engine returns `{treatment, label}`; evaluator attaches config/changeNumber (§4.3)
- **Canonical query order**: network facade MUST emit `s`→`since`→`rbSince`→[`sets`]→[`till`] (§10.4)

## DOs

- Keep the engine pure — all store access flows through `EvaluationContext`
- Preserve `bucketingKey == null` until bucketing time (§4.1)

## DON'Ts

- Don't put matching logic here — that belongs in `engine`
- Don't let `getTreatment` do I/O or throw (§2.2)
