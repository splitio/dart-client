# AGENTS.md — parsing

## Purpose

**Wire DTO deserialization** — Transforms raw JSON responses from the Split API into `ParsedSplit` and `TargetingRule` domain objects. Handles unsupported-matcher detection and gracefully skips invalid splits.

## Key Files

- `parsing.dart` — Library export
- `rule_parser.dart` — Wire rules → `TargetingRule`
- `matcher_parser.dart` — Wire matcher JSON → matcher instances
- `split_change_processor.dart` — Processes `/splitChanges` response payloads
- `memberships_processor.dart` — Processes `/memberships` response payloads

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/parsing/`
- **Focus**: JSON correctness, unsupported matcher detection, malformed input isolation

## Dependencies

- **Internal**: `models`, `core`
- **External**: None
- **Used by**: `sync` (parses API responses before storing)

## Important Patterns

- **Error isolation**: A bad split must not break parsing of other splits — catch per-item
- **Unsupported matchers**: Flag splits with unknown matcher types rather than throwing

## DOs

- Test with real API response fixtures
- Handle every known matcher type; flag unknowns gracefully

## DON'Ts

- Don't throw on unknown matcher types — flag and continue
- Don't add network or storage I/O — pure transformation
