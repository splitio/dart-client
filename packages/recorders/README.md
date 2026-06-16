# recorders

In-memory queue → batch → flush recorder pipeline for impressions, events, unique keys, and impression counts.

## Key exports

| Type | Description |
|---|---|
| `Recorder<T>` | Generic in-memory queue with size/time-based flushing |
| `ImpressionsRecorder` | Deduped impression recorder with 3 modes (OPTIMIZED, DEBUG, NONE) |
| `EventsRecorder` | Events recorder with queuing and batching |
| `UniqueKeysRecorder` | MTK (multi-targeting key) recorder |
| `ImpressionListener` | Optional SPI for user-supplied impression callbacks |

## Dependencies

**Internal:** models  
**External:** none

## Spec reference

SDK Specification v1 §3.1, §13 — Recorders & Impressions
