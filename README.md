# Split Dart SDK

A modular, monorepo-based Dart SDK implementation using [Melos](https://melos.invertase.dev/) for workspaces.

## Prerequisites

- Dart SDK `>=3.0.0 <4.0.0`
- [Melos](https://pub.dev/packages/melos): `dart pub global activate melos`

## Getting Started

```sh
# Install dependencies across all packages
dart run melos run bootstrap

# Install git hooks (run once after cloning)
./scripts/install-hooks.sh
```

## Development

```sh
# Run all tests
dart run melos run test

# Run static analysis
dart run melos run analyze

# Format all code
dart run melos run format

# Collect coverage (enforces ≥80% line coverage)
dart run melos run collect-coverage
```

## Git Hooks

The pre-commit hook (in `scripts/hooks/pre-commit`) runs automatically before every commit:

1. **`melos format`** — formats all Dart code
2. **`melos collect-coverage`** — runs tests, generates coverage, and enforces the 80% line coverage threshold

The commit is blocked if coverage falls below the threshold or any tests fail.

Install the hook once after cloning:

```sh
./scripts/install-hooks.sh
```

## Project Structure

```
dart-client/
├── packages/
│   ├── single-sdk/       # Public SDK entry point
│   ├── sdk_internal/     # Internal DI/wiring root
│   ├── client/           # Per-key SplitClient building block
│   ├── auth/             # Authentication
│   ├── models/           # Shared data types
│   ├── engine/           # Core execution logic
│   ├── http_client/      # HTTP communication layer
│   ├── storage/          # Persistence layer
│   ├── sync/             # Data synchronization
│   ├── observer/         # Observability and logging
│   ├── parsing/          # Data parsing utilities
│   ├── recorders/        # Metrics collection
│   ├── local/            # Local data handling
│   └── e2e/              # End-to-end integration tests
├── scripts/
│   ├── install-hooks.sh  # Installs git hooks
│   └── hooks/
│       └── pre-commit    # Pre-commit hook source
└── docs/                 # Documentation and specs
```

## Documentation

- `AGENTS.md` — AI agent guidelines and project conventions
- `docs/SDK-Specification-v1-RFC2119.md` — Full SDK specification
