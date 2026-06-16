# AGENTS.md — e2e package

## Purpose

**End-to-end integration tests** — Tests the fully assembled SDK against real or simulated backend responses. Validates that all packages work correctly together when wired through `sdk_internal`. Not a publishable package — test infrastructure only.

## Key Files

- `test/` — E2E test files
- `pubspec.yaml` — Depends on `sdk_internal` and/or `single-sdk`
- `fixtures/` — API response fixtures (JSON) used in tests (if present)

## Testing

- **Run e2e tests**: `cd packages/e2e && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Scope**: Full initialization → evaluation → sync → impression recording lifecycle
- **Note**: May require mock HTTP server or fixture-based approach

## Dependencies

- **Internal**: `single-sdk` (tests the full assembly as a real consumer would)
- **External**: `test`, `lints`, `mock_http_server` (simulates Split backend responses)

## Important Patterns

- **Fixture-based**: Use recorded API responses as fixtures — no real network in CI
- **Lifecycle tests**: Test full SDK lifecycle: init → ready → getTreatment → destroy
- **Streaming tests**: Test SSE streaming → storage update → evaluation refresh
- **Cross-package**: These tests validate integration seams that unit tests can't catch

## DOs

- Test the full SDK lifecycle end-to-end
- Use fixture data from real API responses
- Test error paths (network failure, invalid API key, empty response)
- Run these in CI on every PR — they catch integration regressions unit tests miss

## DON'Ts

- Don't make real network calls in CI — use fixtures or mock HTTP server
- Don't duplicate unit test coverage — focus on integration seams
- Don't put business logic in test helpers — keep tests readable
