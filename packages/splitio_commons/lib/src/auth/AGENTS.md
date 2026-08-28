# AGENTS.md — auth

## Purpose

**Per-endpoint credential provisioning** — Auth strategy + JWT cache/fetch for streaming. Leaf module: on-demand credential fetch (no periodic refresh), handles JWT expiry/invalidation. Maps to spec §3.1 `auth`; behavior in §11.3 and §19.3.

## Key Files

- `auth.dart` — Library export
- `auth_provider.dart` — `AuthProvider` port
- `jwt_auth_provider.dart` — `JwtAuthProvider` (cached/deduped/on-demand)
- `credential.dart` — `Credential` / `JwtCredential` value types

## Testing

- **Run tests**: `cd packages/splitio_commons && dart test test/auth/`
- **Focus**: JWT decode/expiry, channel parsing, caching + de-dup of concurrent fetches, push-enabled flag

## Dependencies

- **Internal**: `models`
- **External**: None (`dart:convert` for JWT decode)
- **Used by**: `sync` (streaming JWT)

## Important Patterns

- **Strategy port**: `AuthProvider` abstracts static-key vs JWT provisioning
- **On-demand only**: Fetch when needed; cache until expiry; de-dup concurrent requests
- **`JwtCredential`**: `{ token, channels, pushEnabled, expiresAt, connDelaySeconds }`

## DOs

- Decode JWT without a third-party dep (`dart:convert`); stay platform-agnostic
- Cache and de-duplicate concurrent token fetches
- Treat expiry/invalidation explicitly; never serve a stale token for streaming

## DON'Ts

- Don't perform periodic background refresh — provisioning is on-demand
- Don't add `dart:io`/`dart:html` — must run on all targets
