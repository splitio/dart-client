# AGENTS.md — http_client

## Purpose

**HTTP abstraction + SSE streaming transport SPI** — Wraps the `http` package with SDK-specific concerns. Defines the `StreamingTransport` SPI with platform-specific implementations (IO, Web, stub). Maps to spec §6.

## Key Files

- `http_client.dart` — Library export
- `split_http_client.dart` — Main HTTP client implementation
- `http_status_action.dart` — Per-status-code action enum (retry, stop, etc.)
- `streaming_transport.dart` — `StreamingTransport` SPI (abstract)
- `streaming_transport_factory.dart` — Platform-conditional factory
- `streaming_transport_io.dart` — VM/native implementation
- `streaming_transport_web.dart` — Flutter Web implementation
- `streaming_transport_stub.dart` — Stub for unsupported platforms
- `http_client_testing.dart` + `testing/fake_streaming_transport.dart` — Test doubles

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/http_client/`
- **Focus**: Request formation, status-action mapping, SSE framing, fake transport behavior

## Dependencies

- **Internal**: None
- **External**: `http`, `fetch_client` (Web), `backoff`
- **Used by**: `sync`, `auth`

## Important Patterns

- **Platform SPI**: `StreamingTransport` is injected; never instantiated directly by consumers
- **Test double**: `FakeStreamingTransport` in `testing/` for deterministic streaming tests

## DOs

- Keep the `StreamingTransport` SPI clean — all platform specifics behind implementations
- Expose `http_client_testing.dart` only as a test dependency

## DON'Ts

- Don't add SDK business logic — pure transport
- Don't use `dart:io`/`dart:html` outside the platform-specific impl files
