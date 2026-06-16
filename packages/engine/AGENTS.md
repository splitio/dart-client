# AGENTS.md — engine package

## Purpose

**Pure, stateless rule evaluation** — The matching algorithm. Takes a split definition and a targeting key, returns a treatment. No I/O, no state, no side effects. The computational core of feature flag evaluation.

## Key Files

- `lib/engine.dart` — Library export
- `lib/src/evaluator.dart` — Main evaluation entry point (to be created)
- `lib/src/matcher/` — Matcher implementations (string, set, number, date, etc.)
- `pubspec.yaml` — Depends only on `models`

## Testing

- **Run tests**: `cd packages/engine && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Matcher correctness, evaluation logic, edge cases (null keys, no rules, etc.)
- **Note**: Most critical tests in the SDK — cover every matcher type thoroughly

## Dependencies

- **Internal**: `models` (split definitions, targeting rules)
- **External**: None
- **Used by**: `local` (which binds engine to storage for evaluation)

## Important Patterns

- **Pure functions**: Evaluation takes inputs, returns output — no mutation, no I/O
- **Matcher dispatch**: Each `MatcherType` maps to a concrete matcher implementation
- **Recursive evaluation**: Segments require recursive membership lookup (handled by `local`)
- **Unsupported matchers**: Must handle gracefully (return default treatment, not throw)

## DOs

- Keep all functions pure — no global state, no I/O
- Test every matcher type with positive and negative cases
- Handle unknown/unsupported matchers without throwing
- Use `models` types throughout; don't define new types here
- Optimize the hot path — this code runs on every `getTreatment` call

## DON'Ts

- Don't add I/O, storage access, or network calls
- Don't add state — evaluation must be idempotent
- Don't add dependencies beyond `models`
- Don't throw on unsupported matchers — return default treatment
