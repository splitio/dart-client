# AGENTS.md — http_client package

## Purpose

**Buffered HTTP abstraction** — Implements the HTTP request/response layer (Axis-1 SPI). Wraps the `http` package with buffering, retry, and SDK-specific concerns. Provides a clean interface for the rest of the SDK to make HTTP calls without coupling to a specific HTTP library.

## Key Files

- `lib/http_client.dart` — Library export
- `lib/src/split_http_client.dart` — Main HTTP client implementation (to be created)
- `pubspec.yaml` — Depends on `http: ^1.1.0`

## Testing

- **Run tests**: `cd packages/http_client && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: Request formation, response handling, error/retry behavior, mocking

## Dependencies

- **Internal**: None
- **External**: `http: ^1.1.0`, `fetch_client: ^1.1.1` (Web/Flutter-compatible HTTP via `fetch` API)
- **Used by**: `sdk_internal` (injected into sync and auth at wiring time)

## Important Patterns

- **SPI (Service Provider Interface)**: Defines the interface; injected into consumers
- **Buffering**: Batches or queues requests where appropriate
- **Retry logic**: Configurable retries with backoff for transient failures
- **SSE support**: Must support Server-Sent Events for streaming sync

## DOs

- Define a clean interface/abstract class so consumers can use fakes in tests
- Handle SSE (streaming) and regular HTTP requests through the same interface
- Add appropriate timeouts and error handling
- Test with mock HTTP responses — don't make real network calls in unit tests

## DON'Ts

- Don't add SDK business logic — this is pure transport
- Don't add dependencies on other SDK internal packages
- Don't swallow HTTP errors — surface them to callers
