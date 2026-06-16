# auth

Per-endpoint credential provisioning (auth strategy + JWT caching). Leaf module. On-demand credential fetch (no periodic refresh). Handles JWT expiry/invalidation.

## Key exports

| Type | Description |
|---|---|
| `AuthProvider` | Interface for per-endpoint credential provisioning; port for auth strategy. |
| `StaticKeyAuthProvider` | Static SDK-key bearer token provider. |
| `JwtAuthProvider` | Cached and deduplicated JWT provider for streaming; on-demand fetch with expiry handling. |
| `Credential` | Base credential type carrying auth headers. |
| `JwtCredential` | Extended credential with token, channels, pushEnabled, expiresAt, connDelaySeconds. |

## Dependencies

**Internal:** models (path ref)  
**External:** dart:convert (for JWT decode), possibly jwt package

## Spec reference

SDK Specification v1 §3.1 — Shared core, module catalog (auth)  
SDK Specification v1 §6 — Port & SPI Contracts (AuthProvider)
