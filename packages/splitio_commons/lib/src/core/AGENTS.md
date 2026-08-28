# AGENTS.md — core

## Purpose

**Shared low-level utilities** — Coercion helpers, semver comparison, `EvaluationContext`, `MatchingContext`, and murmur hash implementations (murmur3 + murmur128). Zero dependencies; used across engine, parsing, and sync.

## Key Files

- `core.dart` — Library export
- `coercion.dart` — Type coercion utilities
- `semver.dart` — Semver parsing and comparison
- `evaluation_context.dart` — `EvaluationContext` passed into engine during evaluation
- `matching_context.dart` — `MatchingContext` carrying attributes for matcher dispatch
- `murmur3.dart` — Murmur3 hash (bucketing)
- `murmur128.dart` — Murmur128 hash (membership bitmap, §12.3)

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/core/`
- **Focus**: Hash correctness (reference vectors), semver edge cases, coercion boundary values

## Dependencies

- **Internal**: None (leaf)
- **External**: None

## DOs

- Keep all functions pure and side-effect free
- Validate murmur hash output against known reference vectors
- Avoid `BigInt` on the hot path — web compat (§12.3 uses decimal-string comparison instead)

## DON'Ts

- Don't add dependencies — this must remain a universal leaf
- Don't add `dart:io`/`dart:html`
