# AGENTS.md — logger package

## Purpose

**Logging abstraction** — A thin `Logger` / `LogLevel` facade over `package:logging`. Leaf utility consumed across the SDK so that emitters never depend on a concrete logging backend. Maps to spec §3.1 `logger`.

## Key Files

- `lib/logger.dart` — Library export
- `lib/src/logger.dart` — `Logger` facade (to be created)
- `lib/src/log_level.dart` — `LogLevel` enum (to be created)
- `pubspec.yaml` — Depends on `package:logging` only

## Testing

- **Run tests**: `cd packages/logger && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Level filtering, message formatting, no-op behavior when disabled

## Dependencies

- **Internal**: None (leaf)
- **External**: `package:logging` (approved in `docs/deps.md`)
- **Used by**: Most packages that emit diagnostics

## DOs

- Keep the surface minimal — `Logger` + `LogLevel` only
- Default to a no-op/quiet sink so libraries are silent unless configured
- Stay platform-agnostic (no `dart:io`)

## DON'Ts

- Don't add internal SDK dependencies — this must remain a universal leaf
- Don't print directly; route everything through `package:logging`
- Don't introduce new external deps without sign-off (`docs/deps.md`)
