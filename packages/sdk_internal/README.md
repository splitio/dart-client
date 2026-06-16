# sdk

Composition root (SplitFactory) and public API. Wires all layers: Evaluator (LOCAL), Topology (Client-Side), Platform (http/auth). Validates config and creates SplitClient instances.

## Key exports

| Type | Description |
|---|---|
| `SplitFactory` | DI root; creates clients, manager, manages lifecycle |
| `SplitClient` | Public shell with bound Target; getTreatment, track, events |
| `SplitManager` | Metadata access; splits(), split(flag), names() |
| `SplitView` | Read-only flag metadata projection |
| `UserConsent` | GRANTED/DECLINED/UNKNOWN consent control |
| `SplitClientConfig` | Configuration; grouped, immutable, normalized |

## Dependencies

**Internal:** models, engine, storage, parsing, local, client, sync, recorders, http_client, auth, observer (path refs)  
**External:** none

## Spec reference

SDK Specification v1 §3.1 — SDK package, §7 — Public API, §14 — Configuration
