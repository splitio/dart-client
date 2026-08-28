# AGENTS.md — engine

## Purpose

**Pure, stateless rule evaluation** — The matching algorithm. Takes a split definition and a targeting key, returns a treatment. No I/O, no state, no side effects. Maps to spec §4.

## Key Files

- `engine.dart` — Library export
- `bucketer.dart` — Bucketing logic (murmur3-based traffic allocation)
- `matcher_engine.dart` — Dispatches to per-type matcher implementations
- `targeting_engine.dart` — Walks targeting rules, applies conditions, returns treatment

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/engine/`
- **Focus**: Matcher correctness, evaluation logic, edge cases (null keys, no rules, unsupported matchers)
- **Note**: Most critical tests in the SDK — cover every matcher type thoroughly

## Dependencies

- **Internal**: `models`, `core`
- **External**: None
- **Used by**: `local`

## Important Patterns

- **Pure functions**: Evaluation takes inputs, returns output — no mutation, no I/O
- **Matcher dispatch**: Each `MatcherType` maps to a concrete matcher in `models/matchers/`
- **Unsupported matchers**: Handle gracefully — return default treatment, never throw

## DOs

- Keep all functions pure — no global state, no I/O
- Test every matcher type with positive and negative cases
- Optimize the hot path — this runs on every `getTreatment` call

## DON'Ts

- Don't add I/O, storage access, or network calls
- Don't add state — evaluation must be idempotent
- Don't throw on unsupported matchers — return default treatment
