# local

Binds engine and storage for LOCAL evaluation. Implements Evaluator port, EvaluationContext over stores. Central place for store lookups, recursive eval, and segment membership dispatch.

## Key exports

| Type | Description |
|---|---|
| `LocalEvaluator` | Concrete Evaluator implementation for LOCAL evaluation |
| `LocalEvaluationContext` | Host callback seam for pure engine (recursive eval, segment membership) |
| `LocalNetworkAdapter` | Typed NetworkFacade for LOCAL with canonical query-param ordering |

## Dependencies

**Internal:** engine, storage, parsing, models  
**External:** none

## Spec reference

SDK Specification v1 §3.2 — LOCAL-eval specific (Axis 2 = LOCAL)
