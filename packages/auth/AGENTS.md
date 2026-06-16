# AGENTS.md — auth package

## Purpose

**Per-endpoint credential provisioning** — Auth strategy + JWT cache/fetch for streaming. Leaf module: on-demand credential fetch (no periodic refresh), handles JWT expiry/invalidation. Maps to spec §3.1 `auth`; behavior in §11.3 and §19.3.

## Key Files

- `lib/auth.dart` — Library export
- `lib/src/auth_provider.dart` — `AuthProvider` port (to be created)
- `lib/src/static_key_auth_provider.dart` — `StaticKeyAuthProvider` (sdkKey) (to be created)
- `lib/src/jwt_auth_provider.dart` — `JwtAuthProvider` (cached/deduped/on-demand) (to be created)
- `lib/src/credential.dart` — `Credential` / `JwtCredential` value types (to be created)
- `pubspec.yaml` — Depends on `models` (+ `dart:convert` for JWT decode)

## Testing

- **Run tests**: `cd packages/auth && dart test`
- **Test file pattern**: `*_test.dart` in `test/`
- **Focus**: JWT decode/expiry, channel parsing, caching + de-dup of concurrent fetches, push-enabled flag

## Dependencies

- **Internal**: `models`
- **External**: None (uses `dart:convert` from the SDK)
- **Used by**: `sync` (streaming JWT), `sdk_internal`

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
- Don't add external deps without sign-off (`docs/deps.md`)
