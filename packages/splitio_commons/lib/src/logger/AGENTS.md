# AGENTS.md — logger

## Purpose

**Logging abstraction** — Thin `Logger` / `LogLevel` facade over `package:logging`. Leaf utility consumed across the SDK so emitters never depend on a concrete logging backend. Maps to spec §3.1 `logger`.

## Key Files

- `logger.dart` — `Logger` facade + `LogLevel` enum

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/logger/`
- **Focus**: Level filtering, no-op behavior when disabled

## Dependencies

- **Internal**: None (leaf)
- **External**: `package:logging`
- **Used by**: All subdomains that emit diagnostics

## DOs

- Default to a quiet/no-op sink so the library is silent unless configured
- Stay platform-agnostic (no `dart:io`)

## DON'Ts

- Don't add internal SDK dependencies — must remain a universal leaf
- Don't print directly; route through `package:logging`
