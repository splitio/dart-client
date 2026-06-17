# AGENTS.md

## Project Overview

**Split Dart SDK** — A modular, monorepo-based Dart SDK implementation using Melos for workspaces. The project splits the Dart SDK into specialized, reusable packages organized under `packages/` including core functionality (models, auth, storage), sync engines, HTTP clients, data parsing, and observability tools.

Primary language: **Dart** (3.0.0+)  
Build system: **Melos** (workspaces)  
Test framework: **Dart test package** + e2e testing  
Target platforms: **All Dart targets** — Dart VM, Flutter (Android, iOS, Web, Desktop)

## Build System

- **Build tool**: Melos (Dart workspaces)
- **Root pubspec**: `pubspec.yaml` (dev-only, defines dev_dependencies and Melos workspace config under `melos:` key)
- **Build all packages**: `dart pub get` (in each package) — no `melos build` script exists
- **Build specific package**: `cd packages/[package-name] && dart pub get`
- **Clean all**: `melos clean`
- **Get all dependencies**: `melos bootstrap`

## Testing

- **Run all tests**: `melos test` (runs tests across all packages)
- **Run tests in specific package**: `cd packages/[package-name] && dart test`
- **Run single test file**: `dart test path/to/test_file.dart`
- **Run e2e tests**: `cd packages/e2e && dart test`
- **Test patterns**: Files named `*_test.dart` in `test/` directories
- **Coverage**: `dart run melos collect-coverage` — runs `dart test --coverage` across all packages (excluding e2e), generates per-package `coverage/lcov.info` scoped to `lib/`, merges them into `coverage/lcov.info` at the repo root, and enforces a minimum of **80% line coverage**. Fails if below threshold.
- **Coverage ignore directive**: Barrel files (`lib/<package>.dart`) that have no uncommented `export` lines carry a `// coverage:ignore-file` comment at the top — they have no instrumentable code yet. The `collect-coverage` script removes this directive automatically once real exports are added. Do not remove it manually on empty barrels, and do not add it to `lib/src/` files.

## Linting & Formatting

- **Lint check**: `dart analyze` (in each package or use `melos analyze`)
- **Format check**: `dart format --set-exit-if-changed .`
- **Format fix**: `dart format -w .`
- **Static analysis lints**: Defined by `lints: ^3.0.0` in pubspec.yaml
- **Auto-run after changes**: Pre-commit hooks can run `dart format` and `dart analyze`

## Git Workflow

- **Branch naming**: `feature/JIRA-xxx-description` or `fix/JIRA-xxx-description`
- **Commit format**: `feat|fix|chore|test|docs|refactor: [JIRA-xxx]: Description`
- **PR title format**: Same as commit format
- **Default branch**: `main`
- **Merge strategy**: Squash commits preferred for clarity

## DOs

- Always run `melos test` before committing to ensure no breaking changes across packages
- Use `dart format` to maintain consistent code style across the monorepo
- Follow existing patterns in core packages (models, auth, storage)
- Keep package dependencies minimal — use internal packages when appropriate
- Update CHANGELOG.md in affected packages for user-facing changes
- Write unit tests for all new functions and classes
- Use meaningful commit messages that reference Jira tickets
- Run `dart analyze` to catch linting issues early
- Document public APIs with doc comments (/// for public API)
- Test interdependencies between packages (e2e tests in `packages/e2e`)

## DON'Ts

- Never force-push to main or master branches
- Never commit secrets, .env files, or API credentials
- Never skip linting or tests (`--no-verify` is forbidden)
- Don't modify production-facing configuration files without approval
- Don't add new dependencies to `pubspec.yaml` without considering monorepo impact
- Don't break compatibility between packages — use semantic versioning
- Don't commit `.dart_tool/`, `build/`, `coverage/`, or `.packages` files
- Don't modify version numbers manually — use semantic versioning
- Don't create new packages at the root level; always place them under `packages/`

## Commit Message Rules

- Format: `feat|fix|chore|test|docs|refactor: [JIRA-xxx]: Description`
- **NEVER add `Co-Authored-By` lines** to commit messages — not for any tool, agent, or assistant

## Commands to Never Run

- `git push --force origin main`
- `git push --force origin master`
- `git commit --no-verify` or `git push --no-verify`
- `rm -rf .dart_tool/` without understanding rebuild implications
- `git reset --hard` without explicit confirmation

## Project Structure

```
dart-client/
├── pubspec.yaml              # Root workspace definition (Melos config under `melos:` key)
├── AGENTS.md                 # This file
├── packages/                 # All Dart packages (monorepo structure)
│   ├── models/               # Data models and types
│   ├── auth/                 # Authentication and authorization
│   ├── storage/              # Local storage and persistence
│   ├── http_client/          # HTTP client implementation
│   ├── client/               # Internal per-key SplitClient/ClientManager building block
│   ├── engine/               # Core execution engine
│   ├── sync/                 # Synchronization logic
│   ├── parsing/              # Data parsing utilities
│   ├── recorders/            # Event recording and metrics
│   ├── observer/             # Observability (logging, tracing)
│   ├── logger/               # Logging abstraction over package:logging
│   ├── events/               # Readiness/lifecycle manager (latched events)
│   ├── sdk_internal/         # Internal DI/wiring root; assembles all layers (not published directly)
│   ├── local/                # Local data handling
│   ├── sdk_single/           # Public SDK entry point (the package users install)
│   └── e2e/                  # End-to-end integration tests
├── test/                     # Root-level tests (if any)
└── docs/                     # Documentation
```

## Important Packages/Folders

Based on recent activity and architecture:

| Package | Purpose | Priority |
|---------|---------|----------|
| `packages/sdk_single` | Public SDK entry point; the package users install | High |
| `packages/sdk_internal` | Internal DI/wiring root; assembles all layers | High |
| `packages/client` | Internal per-key SplitClient/ClientManager building block | High |
| `packages/auth` | Authentication logic; security-critical | High |
| `packages/models` | Shared data types across SDK | High |
| `packages/engine` | Core execution logic; complex algorithms | High |
| `packages/http_client` | HTTP communication layer | Medium |
| `packages/storage` | Persistence layer | Medium |
| `packages/observer` | Observability and logging | Medium |
| `packages/sync` | Data synchronization | Medium |
| `packages/e2e` | Integration tests | Medium |
| `packages/parsing` | Data parsing utilities | Low |
| `packages/recorders` | Metrics collection | Low |

## Monorepo Commands (Melos)

- **`melos bootstrap`** — Install dependencies across all packages
- **`melos clean`** — Remove build artifacts from all packages
- **`melos analyze`** — Run dart analyze on all packages
- **`melos test`** — Run tests in all packages
- **`melos format`** — Format all packages
- **`melos collect-coverage`** — Run coverage, merge, enforce 80% threshold
- **`melos publish`** — Publish packages to pub.dev (with workflow prompts)

## Package-Level Guidelines

When working on individual packages:

1. **Understand dependencies**: Check `pubspec.yaml` for internal and external dependencies
2. **Test locally**: Run `dart test` in the package directory before committing
3. **Sync with monorepo**: If changing shared types (models), test impact on dependent packages
4. **Documentation**: Update `README.md` in the package if adding major features
5. **Versioning**: Use semver; patch for fixes, minor for features, major for breaking changes

## Dart-Specific Guidelines

This codebase uses specialized Dart skills available in Claude Code:

- **`dart-run-static-analysis`** — Run dart analyze and lints across packages
- **`dart-add-unit-test`** — Generate unit tests for functions/classes
- **`dart-build-cli-app`** — Build CLI tools (if applicable)
- **`dart-collect-coverage`** — Gather code coverage reports
- **`dart-fix-runtime-errors`** — Debug and fix runtime issues
- **`dart-generate-test-mocks`** — Generate mocks for testing with `mockito`
- **`dart-scaffold-package`** — Create new packages with proper structure
- **`dart-migrate-to-checks-package`** — Migrate to the `checks` package for testing
- **`dart-resolve-package-conflicts`** — Debug and resolve version conflicts
- **`dart-setup-ffi-assets`** — Configure FFI (Foreign Function Interface) bindings
- **`dart-use-ffigen`** — Generate Dart bindings for C libraries
- **`update-spec`** — Guided workflow for changing `docs/SDK-Specification-v1-RFC2119.md`: enforces grill-me before drafting, RFC 2119 language, language-agnostic scope, and user approval before edits
- **`patch-a-bug`** — Workflow for fixing discovered bugs: write failing e2e test first, check spec for contradictions (invoke `update-spec` if needed), then TDD fix with Tidy First discipline

Use these skills when appropriate for your tasks — they handle Dart-specific complexity.

## Development Flow

**Tidy First, then TDD. RED → GREEN → REFACTOR.**

### New Features

Before implementing any feature:
1. **Write the e2e test first** (in `packages/e2e`) if the feature has externally visible behavior — public API changes, observable HTTP requests (via `MockWebServer`), storage side-effects, or any input-to-output behavior at the SDK boundary. It MUST fail before any implementation exists. Commit it alone. Pure internal logic (private helpers, internal algorithms) does not require an e2e test.
2. **Check the spec**: Read `docs/SDK-Specification-v1-RFC2119.md` for the relevant section. If the spec is silent or contradicts the plan, resolve it with `update-spec` before writing code.
3. **Tidy First** — make any structural changes (rename, move, extract interface) as separate commits before adding behavior. Never mix structural and behavioral changes in the same commit.
4. **Write failing unit tests** for the affected packages.
5. **Implement** the minimum code to make tests pass (GREEN).
6. **Refactor** — clean up with tests green; commit separately.

### Bug Fixes & Patches

Use the **`patch-a-bug`** skill. Bug fixes have a different flow from features because they may expose spec oversights in addition to implementation errors:

1. **Step 0 — Failing test first**: If the bug is externally visible (wrong public API behavior, incorrect HTTP requests, storage side-effects), write a failing e2e test in `packages/e2e` before touching any implementation. Commit it alone. Internal-only bugs get a failing unit test in the affected package instead.
2. **Check the spec**: Read `docs/SDK-Specification-v1-RFC2119.md` for the relevant section. If the spec describes the broken behavior, use `update-spec` to correct it before fixing code. Spec and fix land together.
3. **Tidy First** if structural changes are needed — separate commit, no behavior change.
4. **Minimal fix** — RED → GREEN → REFACTOR.
5. **`melos test`** — no regressions across all packages.

## e2e Testing Requirements

Any new functionality that affects the SDK's observable behavior MUST have a corresponding test in `packages/e2e` before the implementation is considered complete. Tests MUST use `mock_http_server` to assert on real HTTP interactions — not mocks of internal components.

Example: on `SplitFactory.create(...)`, the default client MUST trigger a `GET /splitChanges` request. This MUST be asserted in `packages/e2e` by starting a `MockWebServer`, initializing the factory, and verifying the request was received.

This applies to: sync behavior, streaming lifecycle, readiness events, impression/event flushing, auth flows, and any other behavior visible at the SDK boundary.

## Platform Compatibility

This SDK MUST run on every Dart target with as little platform-specific code as possible:

- **Dart VM** (servers, CLI, native apps)
- **Flutter** — Android, iOS, Web, Desktop (macOS, Windows, Linux)
- **Minimum SDK**: `dart: '>=3.0.0 <4.0.0'` — every package MUST maintain this floor

Rules that follow from this:
- **Do not use `dart:io` or `dart:html` directly** in shared packages — they are not available on all targets. Platform-specific I/O MUST be behind an SPI (e.g. `HttpClient`, `StreamingTransport`, `Decompressor` — see spec §6).
- **Avoid `BigInt`** on the hot path — it is heap-allocated and slow on Dart-compiled-to-JS (Flutter Web). The spec (§12.3) already mandates string-comparison workarounds where 64-bit integers would otherwise be needed.
- **New external dependencies MUST be verified to support all targets** before being approved (see External Dependencies below). A dependency that only works on VM or only on Flutter Web is a blocker unless it is explicitly platform-scoped behind an SPI.
- When writing tests, use `package:test` platform annotations (`@TestOn`) if a test is unavoidably platform-specific.

## External Dependencies

Adding a new external dependency (any `pub.dev` package not already present in a `pubspec.yaml`) MUST be raised with the user before adding it. It is a conscious architectural decision — not a convenience shortcut.

Before proposing a new dependency, consider whether the need can be met by:
- An already-approved dependency in another package
- A small amount of hand-written code

If a new dependency is genuinely needed, surface it explicitly: name the package, explain why it is needed, and wait for user approval before modifying any `pubspec.yaml`.

The approved external dependencies for this project are defined in `docs/deps.md`. Any addition beyond that list requires explicit user sign-off.

## Public API Stability

The public API surface (defined in `packages/sdk_single` and specified in `docs/SDK-Specification-v1-RFC2119.md` §7) MUST NOT be changed casually. This includes `SplitFactory`, `SplitClient`, `SplitManager`, `SplitView`, `SplitClientConfig`, and all their method signatures and return types.

If a proposed change — including changes made to simplify e2e testing — requires altering the public API, stop and raise it explicitly with the user before proceeding. Testing convenience is never a sufficient reason to change the API contract.

Acceptable reasons to change the public API:
- The spec explicitly requires it
- A confirmed bug in the spec or API design, agreed with the user
- A deliberate, user-approved design revision

## Spec Compliance & Sync

`docs/SDK-Specification-v1-RFC2119.md` and the implementation MUST stay in sync at all times. Neither is allowed to drift from the other silently.

**When a conflict arises between a user instruction and the spec:**
1. Flag the conflict explicitly before proceeding.
2. Ask the user to clarify: adjust the implementation plan, or correct the spec.
3. The spec is almost always correct — but it can be wrong; the user decides which takes precedence.
4. Never silently implement something that contradicts the spec.

**When the spec must be updated** (e.g. a wrong design decision is discovered during implementation):
1. Raise it with the user before touching the spec.
2. The user must explicitly approve the change.
3. Updates MUST preserve the spec's format and RFC 2119 normative language (`MUST`, `MUST NOT`, `SHOULD`, `MAY`, etc.). Do not weaken normative language without a deliberate reason.
4. The corresponding implementation change and the spec update MUST land together — never one without the other.

## End-of-Session

At the end of each session or after a task wraps up, ask the user: **"Do you want to revise any AGENTS.md or README.md files to reflect what we built or decided?"**

## When to Ask for Help

- Testing patterns across packages (especially e2e)
- Resolving version conflicts in monorepo
- Package dependency restructuring
- Performance profiling or optimization
- Observability and logging patterns
