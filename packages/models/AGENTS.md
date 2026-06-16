# AGENTS.md — models package

## Purpose

**Shared domain types** — Domain objects, enums, DTOs, and data transfer types used across all SDK packages. Zero dependencies (leaf package). Every other package may depend on this; changes here have wide impact.

## Key Files

- `lib/models.dart` — Main export of all public types
- `lib/src/` — Individual model files (SplitView, EvaluationResult, config types, etc.)
- `pubspec.yaml` — No internal dependencies (leaf)

## Testing

- **Run tests**: `cd packages/models && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Serialization/deserialization, equality, fromJson/toJson

## Dependencies

- **Internal**: None (leaf — no internal deps)
- **External**: None
- **Used by**: Every other package in the SDK

## Important Patterns

- **Immutable value objects**: Prefer `final` fields and `const` constructors
- **Equality**: Implement `==` and `hashCode` for types used as map keys or in sets
- **Serialization**: `fromJson`/`toJson` for wire DTOs; pure model types stay clean
- **Enums**: Use Dart enums for fixed sets (treatment values, user consent states, etc.)

## DOs

- Keep models pure — no business logic, no I/O
- Add `fromJson`/`toJson` to DTOs used in parsing/HTTP layers
- Use `const` constructors where possible
- Document all public fields with doc comments
- Test JSON round-trips for all DTOs

## DON'Ts

- Never add dependencies on other SDK packages (this is a leaf)
- Don't add business logic — this is a types-only package
- Don't change field names in DTOs without updating all callers across the monorepo
- Don't break existing types without a major version bump — models are used everywhere
