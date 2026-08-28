# Plan: Implement `track` event

## Decisions confirmed
1. **Public API**: `track(String eventType, String trafficType, {double? value, Map<String, Object?>? properties})` — mirrors splitio-commons. This changes the current stub signature in `packages/client/lib/src/split_client.dart:109` — spec §7 must also be updated via `update-spec` since it currently lists `track` with `attributes` instead of `trafficType`.
2. **New package**: `packages/event_tracker/` (name avoids collision with existing `packages/events/` which is the readiness/lifecycle manager). Contains: `Event` model + wire mapping, `EventsStore`, `EventsTracker`, input validation.

## Reference from `javascript-commons`
- `src/utils/inputValidation/event.ts` — `eventTypeId` regex `^[a-zA-Z0-9][-_.:a-zA-Z0-9]{0,79}$`
- `src/utils/inputValidation/eventProperties.ts` — max 300 keys, max 32KB total, base 1KB, values only string/number/bool/null
- `src/storages/inMemory/EventsCacheInMemory.ts` — queue with `MAX_QUEUE_BYTE_SIZE = 5MB`, `onFullQueue` callback
- `src/trackers/eventTracker.ts` — consent gate, queue, telemetry stat
- `src/sync/submitters/eventsSubmitter.ts` — periodic push + full-queue push
- `src/services/splitApi.ts` — `POST {events}/events/bulk`
- `src/sdkClient/client.ts:185` — `track(key, trafficType, eventTypeId, value?, properties?, size=1024)`

## Wire shape (from spec §4.5, §A.5)
```
Event { eventTypeId, trafficTypeName, key, value?, properties?, timestamp } → POST /events/bulk
```

## Package layout

```
packages/event_tracker/
├── pubspec.yaml
├── lib/
│   ├── event_tracker.dart          # barrel
│   └── src/
│       ├── event.dart              # Event model {eventTypeId, trafficTypeName, key, value?, timestamp, properties?}
│       ├── events_store.dart       # EventsStore + InMemoryEventsStore (queue + byte tracking)
│       ├── events_tracker.dart     # EventsTracker.track(Event) → consent gate + store
│       └── event_validator.dart    # validateEvent, validateTrafficType, validateProperties
└── test/
    ├── event_validator_test.dart
    ├── events_store_test.dart
    └── events_tracker_test.dart
```

## Sequence (Tidy First, TDD)

### Step 0 — Update spec (`update-spec` skill)
- §7 `SplitClient.track` signature: `bool track(String eventType, String trafficType, {double? value, Map<String, Object?>? properties})`
- Confirm consent-declined returns `false`; queue-full returns `false`; validation failure returns `false`.

### Step 1 — RED: e2e test (`packages/e2e/test/events_e2e_test.dart`)
- Extend `MockBackend` with `eventRequests` capture for `POST /events/bulk`.
- Test: `factory.client(key).track('purchase', 'user', value: 9.99, properties: {'sku': 'abc'})` → destroy → assert bulk POST body matches `[{key, trafficTypeName, eventTypeId, value, timestamp, properties}]`.
- Test: empty `eventType` → returns `false`, no request.
- Test: invalid regex → returns `false`.
- Commit alone (fails).

### Step 2 — Scaffold `event_tracker` package (`dart-scaffold-package` skill)
- Add to Melos workspace; deps: `models`, `logger`.

### Step 3 — Model
- `Event` in `event_tracker/lib/src/event.dart` with `toJson()` producing the wire shape (§A.5).
- Export from barrel.

### Step 4 — Validator (RED → GREEN unit tests)
- `validateEventType(String)` — regex `^[a-zA-Z0-9][-_.:a-zA-Z0-9]{0,79}$`, non-empty, non-null.
- `validateTrafficType(String)` — non-empty, lowercased (splitio-commons behavior).
- `validateProperties(Map?)` — ≤300 keys, values ∈ {String, num, bool, null}, invalid → coerced to null, base 1024B + summed size ≤ 32KB, else reject.
- Returns `ValidationResult { Event? event, int size }` or failure.

### Step 5 — Store
- `EventsStore` interface: `bool push(Event, int size)`, `List<Event> popAll()`, `int get count`, `bool get isEmpty`.
- `InMemoryEventsStore` — queue with `_maxQueueBytes = 5 * 1024 * 1024`, drops (returns false) when full; `onFullQueue` callback for future submitter flush trigger.

### Step 6 — Tracker
- `EventsTracker({ EventsStore store, ConsentStatus Function() consentProvider, SplitLogger log })`.
- `bool track(Event, int size)` — consent gate → `store.push` → log info/error.

### Step 7 — Recorder (`packages/sync/lib/src/recorders/events_recorder.dart`)
- Mirrors `ImpressionsRecorder` structure.
- `flush()`: popAll → batches of 500 → `POST $eventsUrl/events/bulk` with JSON array of `event.toJson()`.
- Export from `sync.dart`.
- Unit tests in `packages/sync/test/events_recorder_test.dart`.

### Step 8 — Wire into `SplitClientImpl.track` (`packages/client`)
- Add `event_tracker` dep to `packages/client/pubspec.yaml`.
- Replace stub at `packages/client/lib/src/split_client.dart:109-118`:
  - Validate → build `Event { eventTypeId, trafficTypeName, key: _key.matchingKey, value, timestamp: now, properties }` → `_eventsTracker.track(event, size)`.
- Update `SplitClient` abstract signature.
- Update `SplitClientImpl` constructor to accept `EventsTracker`.

### Step 9 — DI wiring (`packages/sdk_internal/lib/src/dependency_container.dart`)
- Instantiate `InMemoryEventsStore`, `EventsTracker`, `EventsRecorder(pushRate: syncConfig.eventsPushRate)`.
- Add `EventsRecorder` to `SyncManager.recorders` — flush-on-destroy already runs through `stopRecorders()`.
- Pass `EventsTracker` into every `SplitClientImpl` instantiation.

### Step 10 — Green e2e
- Run `melos test`, confirm the RED e2e now passes plus no regressions.

## Non-goals for this PR
- Telemetry `recordEventStats(QUEUED|DROPPED)` — the impressions path stubs telemetry too; keep consistent, leave as `@TODO`.
- `onFullQueueCb` immediate submit — wire the callback, but treat batching-timer flush as sufficient for v1 (matches current impressions behavior).
- Retry semantics — `Recorder` base has none today; do not diverge.

## Files touched
- **New**: `packages/event_tracker/**`, `packages/sync/lib/src/recorders/events_recorder.dart`, `packages/e2e/test/events_e2e_test.dart`
- **Modified**: `packages/sync/lib/sync.dart`, `packages/client/lib/src/split_client.dart`, `packages/client/pubspec.yaml`, `packages/sdk_internal/lib/src/dependency_container.dart`, `packages/sdk_internal/pubspec.yaml`, `packages/e2e/test/helpers/mock_backend.dart`, `docs/SDK-Specification-v1-RFC2119.md` (§7)
- **Root**: `pubspec.yaml` (Melos workspace entry)
