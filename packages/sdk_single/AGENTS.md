# AGENTS.md — sdk_single package

## Purpose

**Public SDK entry point** — The package end users install (`sdk_single`). Re-exports the public API assembled by `sdk_internal` and exposes model types from `models`. This is the only package that should be imported by applications using the Split SDK.

## Key Files

- `lib/sdk_single.dart` — Main library file; re-exports public API and model types
- `lib/src/` — Public-facing wrappers (to be populated)
- `pubspec.yaml` — Package definition; depends on `sdk_internal` and `models`
- `README.md` — User-facing documentation

## Testing

- **Run tests**: `cd packages/sdk_single && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Integration-level tests; also fully covered by `packages/e2e`

## Dependencies

- **Internal**: `sdk_internal` (DI/wiring root), `models` (re-exported types)
- **External**: None (kept thin intentionally)
- **Role**: Facade over `sdk_internal` — no business logic here

## Important Patterns

- **Re-export pattern**: `export 'package:sdk_internal/...';` — public surface lives here, implementation in `sdk_internal`
- **Model re-exports**: Re-exports `models` types so users only import this one package
- **Thin layer**: Contains no logic — only wiring and exports

## DOs

- Keep this package thin — logic belongs in `sdk_internal` or deeper layers
- Re-export all user-facing types (config, client, manager, split views)
- Document the public API in README.md
- Maintain semver carefully — this is the user-facing contract
- Coordinate changes with `sdk_internal` and `models`

## DON'Ts

- Don't add business logic here
- Don't depend on internal packages directly (only `sdk_internal` and `models`)
- Don't break the public API without a major version bump
- Don't expose internal implementation details
