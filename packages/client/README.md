# client

Public SplitClient (bound target), ClientManager (per-Key registry), setTarget. CS-specific. One client per Key (or global in SS, future). Ref-counts shared sync.

## Key exports

| Type | Description |
|---|---|
| `SplitClient` | Client shell with bound Target; synchronous evaluation (`getTreatment`, `getTreatments`, `getTreatmentsByFlagSets`); `setTarget`, `track`, `events`, `flush`, `destroy` |
| `ClientManager` | Per-Key registry; ref-counts shared sync; manages client lifecycle (`getOrCreate`, `destroy`, `destroyAll`) |
| `UniqueKeysTracker` | Interface for tracking unique keys (CS: in-memory set) |

## Dependencies

**Internal:** models, engine, local, storage (path refs)  
**External:** none

## Spec reference

SDK Specification v1 §3.3 — Client-Side specific (Axis 3)
