# AGENTS.md — splitio_commons package

## Purpose

Consolidated shared library — all domain logic previously split across individual packages now lives here as subdirectories under `lib/src/`. Read the per-subdomain file for detail; this index exists so agents load only what they need.

## Subdomain Map

| Subdirectory | AGENTS.md | What it does |
|---|---|---|
| `lib/src/auth/` | [auth/AGENTS.md](lib/src/auth/AGENTS.md) | JWT credential provisioning + caching for streaming |
| `lib/src/core/` | [core/AGENTS.md](lib/src/core/AGENTS.md) | Shared utilities: coercion, semver, EvaluationContext, MatchingContext, murmur hashes |
| `lib/src/engine/` | [engine/AGENTS.md](lib/src/engine/AGENTS.md) | Pure stateless rule evaluation + matcher dispatch |
| `lib/src/event_tracker/` | [event_tracker/AGENTS.md](lib/src/event_tracker/AGENTS.md) | Custom event tracking: validation, batching, flushing |
| `lib/src/events/` | [events/AGENTS.md](lib/src/events/AGENTS.md) | Readiness/lifecycle manager (milestone-latched public stream) |
| `lib/src/http_client/` | [http_client/AGENTS.md](lib/src/http_client/AGENTS.md) | HTTP abstraction + SSE streaming transport SPI |
| `lib/src/impressions/` | [impressions/AGENTS.md](lib/src/impressions/AGENTS.md) | Impression recording with strategy pattern (debug/optimized/none) |
| `lib/src/input_validation/` | _(inline below)_ | Pure validator functions for all SDK inputs; returns `ValidationResult<T>` — never throws |
| `lib/src/local/` | [local/AGENTS.md](lib/src/local/AGENTS.md) | LOCAL-eval wiring: binds engine to storage via EvaluationContext |
| `lib/src/logger/` | [logger/AGENTS.md](lib/src/logger/AGENTS.md) | Thin Logger/LogLevel facade over package:logging |
| `lib/src/models/` | [models/AGENTS.md](lib/src/models/AGENTS.md) | Shared domain types, DTOs, enums — zero dependencies |
| `lib/src/observer/` | [observer/AGENTS.md](lib/src/observer/AGENTS.md) | Generic pub/sub primitive — zero dependencies |
| `lib/src/parsing/` | [parsing/AGENTS.md](lib/src/parsing/AGENTS.md) | Wire DTO deserialization → ParsedSplit / TargetingRule |
| `lib/src/storage/` | [storage/AGENTS.md](lib/src/storage/AGENTS.md) | Generic change-based stores + PersistentStore SPI |
| `lib/src/sync/` | [sync/AGENTS.md](lib/src/sync/AGENTS.md) | Inbound freshness coordinator: polling + SSE streaming FSM |

## input_validation subdomain

Pure, stateless validator functions. One file per input type, all in `lib/src/input_validation/`. **Never throw** — always return `ValidationResult<T>`.

### Key types

- **`ValidationResult<T>`** (`result.dart`) — generic carrier: `value`, `warning`, `error`, `code` (`LogCode`), `isValid` getter.
- **`LogCode`** (`result.dart`) — enum mirroring javascript-commons log codes (200-range = warnings, 300-range = errors).

### Validators

| File | Function(s) | What it validates |
|---|---|---|
| `key.dart` | `validateKey` | `Key` matchingKey/bucketingKey — null, empty, >1024 chars |
| `flag_name.dart` | `validateFlagName` | Single flag name — null, empty, leading/trailing whitespace (warn+trim) |
| `flag_names.dart` | `validateFlagNames` | List of flag names — null/empty list, drops invalids, dedupes (first-seen order) |
| `flag_set.dart` | `validateFlagSet` / `validateFlagSets` | Flag set names — regex `^[a-z0-9][_a-z0-9]{0,49}$`, auto-lowercase with warn, dedup+sort |
| `attributes.dart` | `validateAttributes` | Attribute map — drops empty string keys with warn; values pass through unchanged |
| `operational.dart` | `validateIfNotDestroyed` / `validateIfReady` | Client lifecycle state guards |
| `event_type.dart` | `validateEventType` | Event type string format |
| `traffic_type.dart` | `validateTrafficType` | Traffic type — lowercases with warn |
| `event_value.dart` | `validateEventValue` | Event numeric value — must be finite |
| `event_properties.dart` | `validateProperties` | Event properties map — ≤300 keys, ≤32KB, coerces unsupported value types to null |

### Design rules

- Validators accept nullable inputs; callers do not need null guards before calling.
- Attribute values are **not** validated beyond key presence — engine coercion handles type coercion per spec §5.
- `validateIfReady` returns a warning result (not failure) — the call still proceeds with a `control` treatment.
- All validators are exported from `lib/splitio_commons.dart`.

## Testing

- **Run all tests**: `cd packages/splitio_commons && dart test`
- **Run subdomain tests**: `dart test test/<subdomain>/`
- **Run input_validation tests**: `dart test test/input_validation/`
- **Test file pattern**: `*_test.dart` in `test/<subdomain>/`
