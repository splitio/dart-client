# AGENTS.md — sdk_internal package

## Purpose

**Internal DI root and wiring layer** — Assembles all SDK layers (engine, storage, sync, auth, client, recorders, etc.) into a working SDK instance. Not published to pub.dev (`publish_to: none`). Used exclusively by `single-sdk` (the public entry point). The "composition root" of the SDK.

## Key Files

- `lib/sdk_internal.dart` — Main library; exports wired SDK components
- `lib/src/split_factory.dart` — Factory that creates/wires SDK instances (to be created)
- `pubspec.yaml` — Depends on ALL internal packages

## Testing

- **Run tests**: `cd packages/sdk_internal && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Wiring correctness; integration tests live in `packages/e2e`

## Dependencies

All internal packages (this is the wiring root):
- `models`, `engine`, `storage`, `parsing`, `local` — core evaluation stack
- `client` — per-key SplitClient/ClientManager building block
- `sync` — freshness/streaming coordinator
- `recorders` — impression/event pipeline
- `http_client` — HTTP abstraction
- `auth` — credential provisioning
- `observer` — internal pub/sub

## Important Patterns

- **Composition root**: Only package that knows about all other packages
- **Dependency injection**: Constructs and wires all components; no business logic
- **Factory pattern**: `SplitFactory` creates configured SDK instances
- **Not yet published**: `publish_to: none` during development — must be published alongside `single-sdk` before release (pub.dev requires version deps, not path deps)

## DOs

- Keep this as pure wiring — no business logic
- Initialize all components with proper lifetimes (singletons vs per-key instances)
- Document the wiring graph when it grows complex
- Test that the assembled SDK behaves end-to-end (delegate heavy testing to e2e)

## DON'Ts

- Don't add business logic — delegate to the appropriate layer package
- Don't export this package in `single-sdk` beyond what's needed for the public API
- Don't encourage direct use — document it as an internal package in README.md
- Before publishing `single-sdk`, remove `publish_to: none` and publish `sdk_internal` first (pub.dev requires all dependencies to be published with version constraints, not path deps)
- Don't create circular dependencies
