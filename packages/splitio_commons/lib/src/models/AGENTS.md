# AGENTS.md — models

## Purpose

**Shared domain types** — Domain objects, enums, DTOs, and data transfer types used across all subdomains. Zero dependencies. Every other subdomain may depend on this; changes here have wide impact.

## Key Files

- `models.dart` — Main export of all public types
- `parsed_split.dart`, `partition.dart`, `condition.dart`, `target.dart` — Rule/split DTOs
- `matcher.dart` — `Matcher` base + `MatcherType` enum
- `matchers/` — One file per matcher type (each owns its `match()` logic)
- `evaluation_result.dart`, `impression.dart` — Evaluation output types
- `split_view.dart` — Public `SplitView` type
- `config.dart` — `SplitClientConfig`
- `enums.dart` — `ImpressionsMode`, `ConsentStatus`, `DataType`, `ConditionType`, `CombinerEnum`
- `log_level.dart`, `labels.dart`, `attributes.dart`, `key.dart`

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/models/`
- **Focus**: Serialization round-trips, equality, fromJson/toJson

## Dependencies

- **Internal**: None (leaf — no internal deps)
- **External**: None

## Important Patterns

- **Immutable value objects**: `final` fields, `const` constructors where possible
- **One file per matcher**: each `matchers/*.dart` implements its own `match()` method

## DOs

- Keep models pure — no business logic, no I/O
- Implement `==` and `hashCode` for types used as map keys
- Document all public fields with doc comments (`///`)

## DON'Ts

- Never add dependencies on other subdomains (this is a leaf)
- Don't change DTO field names without updating all callers across the codebase
