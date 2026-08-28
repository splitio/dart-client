# Spec Module → Package Traceability Map

**Purpose:** Single source of truth mapping every module in `SDK-Specification-v1-RFC2119.md` §3 (and the public shell / SPIs) to a concrete location on disk. An agent implementing any spec section should route through this table — no mental translation required.

**Mapping strategy (hybrid):** Substantial, axis-bearing spec modules are their own Dart packages. Small/sub-ordinate modules are **named directories or libraries inside the owning package** rather than separate packages, to avoid monorepo overhead. Both forms are recorded below so routing is unambiguous.

Legend — **Form**: `package` = top-level `packages/<name>/`; `dir` = directory under a parent package's `lib/src/`; `lib` = additional importable library inside a package.

## §3.1 Shared core (no axis)

| Spec module | Form | Location | Notes |
|---|---|---|---|
| `models` | package | `packages/models/` | |
| `dtos` | dir | `packages/models/lib/src/dto/` | Wire/serialization types live inside `models` |
| `parsing` | package | `packages/parsing/` | |
| `engine` | package | `packages/engine/` | Pure, zero-dep matcher engine |
| `events` | package | `packages/events/` | Readiness/lifecycle manager — latched Futures for milestones, broadcast Stream for updates (`EventsManager`: onReady/onTimeout: Completers; onUpdated: broadcast StreamController<List<String>>) |
| `observer` | package | `packages/observer/` | |
| `logger` | package | `packages/logger/` | Over `package:logging` (was previously homeless) |
| `backoff` | external | `package:backoff` (dep of `http_client`) | Exponential backoff math; satisfied by pub `backoff` ^1.0.1 instead of a hand-rolled package. `FixedIntervalBackoffCounter` (not in pub backoff) to be added in `http_client/lib/src/retryable/` if needed |
| `auth` | package | `packages/auth/` | |
| `retryable-http` | dir | `packages/http_client/lib/src/retryable/` | Retry **policy** + status taxonomy (§10.3) over the `HttpClient` SPI; uses `package:backoff` for timing |
| `storage-core` | package | `packages/storage/` | Package named `storage` |
| `recorders` | package | `packages/recorders/` | |
| `sync` | package | `packages/sync/` | Includes `SyncManager`, `StreamingManager`, `OnDemandFetchCoordinator`, `StreamingPolicy` |

## §3.2 LOCAL-eval specific (Axis 2 = LOCAL) — all inside `packages/local/`

| Spec module | Form | Location |
|---|---|---|
| `local-evaluator` | dir | `packages/local/lib/src/evaluator/` |
| `rules` | dir | `packages/local/lib/src/rules/` |
| `local-network` | dir | `packages/local/lib/src/network/` |
| `local-notifications` | dir | `packages/local/lib/src/notifications/` |

## §3.3 Client-Side specific (Axis 3 = CS)

| Spec module | Form | Location |
|---|---|---|
| `cs-client` | dir | `packages/client/lib/src/client/` |
| `client-manager` | dir | `packages/client/lib/src/manager/` |
| `memberships` | dir | `packages/client/lib/src/memberships/` |
| `cs-unique-keys` | dir | `packages/recorders/lib/src/unique_keys/` |

## Public shell / composition root (spec §7, §8)

| Concept | Form | Location | Notes |
|---|---|---|---|
| `SplitFactory` + DI/wiring | package | `packages/sdk_internal/` | Composition root; depends on all layers; `publish_to: none` |
| Public API surface | package | `packages/sdk_single/` | The package users install (pub name `sdk_single`) |
| E2E harness | package | `packages/e2e/` | Tests `sdk_single` from outside |

## Ports & SPIs (spec §6, §3.4)

| Port / SPI | Home package | v1 default |
|---|---|---|
| `Evaluator` / `EvaluationContext` | `local` | LOCAL impl |
| `HttpClient` (Axis 1) | `http_client` | real HTTP |
| `StreamingTransport` (Axis 1) | `sync` | SSE over HTTP |
| `AuthProvider` | `auth` | Static + JWT |
| `PersistentStore` (Axis 1) | `storage` | **no-op** |
| `UniqueKeysTracker` | `recorders` | CS set |
| `ImpressionListener` | `recorders` | optional callback |
| `Decompressor` (Axis 1) | `sync` | gzip/zlib |

## Reserved seams (declared, not implemented in v1 — spec §3.4, §17.2)

`RemoteEvaluator`, remote `NotificationProcessor` (`EVALUATION_UPDATE`), SS shell, global `SegmentStore`, SS bloom `UniqueKeysTracker`, telemetry recorder — declared via the ports above; no package or directory exists in v1.

---

**Maintenance rule:** Any change to package structure, or to spec §3, MUST update this table in the same change. This file is what keeps the three artifacts (spec §3, `PACKAGE-STRUCTURE-v1-design.md`, and `packages/` on disk) from drifting.
