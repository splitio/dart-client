# sdk_single

Split feature-flag SDK for Dart (client-side, single-tenant topology). Synchronous evaluation, streaming sync with polling fallback, impressions, and events.

## Public API

```dart
import 'package:sdk_single/sdk_single.dart';

final factory = SplitFactory.create(sdkKey, config);
final client = factory.client(targetKey: 'user123');
final result = client.getTreatment('my-feature-flag');
print(result.treatment); // 'on' or 'off'
```

## Key exports

| Type | Description |
|---|---|
| `SplitFactory` | Composition root; creates SDK instance and manages clients |
| `SplitClient` | Per-target client; synchronous `getTreatment()` evaluation |
| `SplitManager` | Read-only metadata view of stored flags and configurations |
| `SplitView` | Flag metadata (name, treatments, configs, change number) |
| `UserConsent` | Gating for impressions/events transmission (GRANTED/DECLINED/UNKNOWN) |
| `SplitClientConfig` | Configuration: sync mode, polling rates, impressions mode, etc. |

## Architecture

- **Evaluator:** LOCAL (pure, stateless engine over in-memory stores)
- **Topology:** Client-Side (one client per target key, bound target)
- **Sync:** Polling + streaming (with FSM, JWT auth, on-demand fetch + CDN bypass)
- **Recorders:** Impressions (3 modes: OPTIMIZED/DEBUG/NONE), events, unique keys
- **Consistency:** Single isolate, event-loop atomicity; lock-free

## Dependencies

**Internal:** sdk_internal (wiring), models (domain types)  
**External:** none (at package level; internal layers use package:http for network I/O)

## Spec reference

SDK Specification v1 — §3.3 (Client-Side topology), §7 (Public API), §8 (Lifecycle)
