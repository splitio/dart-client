# AGENTS.md — parsing package

## Purpose

**Wire DTO deserialization** — Transforms raw wire DTOs (JSON responses from Split API) into `ParsedSplit` and `TargetingRule` domain objects. Handles unsupported-matcher detection and gracefully skips invalid splits.

## Key Files

- `lib/parsing.dart` — Library export
- `lib/src/split_parser.dart` — Wire DTO → ParsedSplit (to be created)
- `lib/src/matcher_parser.dart` — Wire rules → TargetingRule (to be created)
- `pubspec.yaml` — Depends on `models`

## Testing

- **Run tests**: `cd packages/parsing && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: JSON parsing correctness, unsupported matcher detection, malformed input handling

## Dependencies

- **Internal**: `models` (ParsedSplit, TargetingRule, matcher types)
- **External**: None
- **Used by**: `sync` (parses API responses before storing), `local` (may parse on demand)

## Important Patterns

- **Null safety**: API responses may have missing or null fields — handle defensively
- **Unsupported matchers**: Flag splits with unknown matcher types rather than throwing
- **Immutable output**: Parsed types should be immutable value objects
- **Error isolation**: A bad split should not break parsing of other splits

## DOs

- Test with real API response fixtures
- Handle every known matcher type; flag unknowns gracefully
- Isolate parse errors per split — don't fail all splits due to one bad one
- Keep parsing logic separate from model definitions (models stay clean)

## DON'Ts

- Don't throw on unknown matcher types — flag them and continue
- Don't add network or storage I/O — this is pure transformation
- Don't mutate input data
