# AGENTS.md — client package

## Purpose

**Client-Side shell (Axis 3 = CS)** — The public `SplitClient` bound to a `Target`, the per-`Key` `ClientManager` registry (ref-counts shared sync, mutates the streaming channel set), and per-`Key` membership storage. Maps to spec §3.3.

## Hybrid sub-module layout

This package consolidates the spec §3.3 CS modules as directories under `lib/src/` (see `docs/SPEC-MODULE-MAP.md`):

| Spec §3.3 module | Path | Key contracts |
|---|---|---|
| `cs-client` | `lib/src/client/` | `SplitClient.getTreatment(flag, opts)` |
| `client-manager` | `lib/src/manager/` | `ClientManager.getOrCreate/destroy/destroyAll` |
| `memberships` | `lib/src/memberships/` | `MembershipStore`, `MembershipFeed`, `MembershipPayloadDecoder` |

> Note: `cs-unique-keys` (the CS set-based MTK tracker) lives in the `recorders` package (`UniqueKeysTracker`), not here.

## Testing

- **Run tests**: `cd packages/client && dart test`
- **Focus**: per-Key client lifecycle, ref-counted shared sync, channel-set mutation on create/destroy, membership decode/strategies (§12.2)

## Dependencies

- **Internal**: `models`, `engine`, `local`, `storage`
- **External**: None
- **Used by**: `sdk_internal`

## Important Patterns

- **One client per `Key`**: `ClientManager` ref-counts shared sync across clients
- **Streaming coupling**: creating/destroying a client mutates the auth/channel set (§8.3)
- **Membership strategies**: 4 strategies for MS + LS (LS is CS-only) (§12.2)

## DOs

- Keep `getTreatment` synchronous, pure, non-throwing (delegate eval to `local`/`engine`)
- Ref-count shared sync correctly; tear down on last destroy
- Preserve per-`Key` isolation of memberships

## DON'Ts

- Don't implement matching or sync here — delegate to `engine`/`local`/`sync`
- Don't change the public API casually (spec §7) — raise it first
- Don't add dependencies beyond models/engine/local/storage
