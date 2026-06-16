# engine

Pure, stateless rule evaluation. The matching algorithm. No I/O, no state mutation.

## Key exports

| Type | Description |
|---|---|
| `TargetingEngine` | Pure rule evaluation; deterministic, ordered algorithm matching targeting rules against targets and attributes |
| `EvaluationContext` | Host callback seam; allows engine to reach storage for segment membership and recursive evaluation |
| `Bucketer` | Deterministic hashing and treatment selection using murmur3 and legacy algorithms |
| `MatcherRegistry` | Registry of all matcher implementations; resolves matcher types from wire format |
| `Matcher` (interface) | Base interface for all matchers; implementations for all targeting semantics (whitelist, segments, numeric, regex, semver, etc.) |

## Dependencies

**Internal:** models  
**External:** none

## Spec reference

SDK Specification v1 §3.1 — Shared core (engine)  
SDK Specification v1 §5 — Evaluation Boundary & Flow
