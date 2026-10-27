2.0.0 (October 27, 2026)
 - BREAKING - `getTreatments`, `getTreatmentsWithConfig` and their `ByFlagSets` variants return a `Map` keyed by flag name instead of a `List`.
 - BREAKING - `logLevel` defaults to `LogLevel.none`.
 - BREAKING - Keys are trimmed and limited to 250 characters (was 1024).
 - BREAKING - `factory.client(key)` with an invalid key returns a NoOp client instead of the main client.
 - Readiness, `whenTimeout()` and `whenUpdated()` are tracked per client.
 - Compressed streaming notifications are applied without a fetch.
 - Logs a warning when more than one factory is created.
 - Bugfixes for readiness, streaming, recorders, validation, matchers and archived flags.

1.1.0 (September 9, 2026)
 - updated `splitio_commons` to `^2.0.0`.

1.0.0 (August 28, 2026)
Initial release. Client-side Dart SDK for Split feature flags. Features:
 - Synchronous local evaluation via SplitFactory.create + per-key SplitClient.
 - Public API: getTreatment / getTreatments / getTreatmentsByFlagSets and their WithConfig variants.
 - Event tracking via SplitClient.track (with optional value and properties).
 - Readiness lifecycle: whenReady(), whenTimeout(), and broadcast whenUpdated() with changed flag names.
 - SplitManager: split(), splits(), names() with read-only SplitView projection.
 - Per-client destroy() (main, shared) plus factory-level destroy() with recorder flush.
 - flush() to force-send queued impressions and events.
 - Full matcher set: user-defined segments, rule-based segments, large segments, dependency, prerequisites, semver, sets, and attribute matchers.
 - Streaming sync (SSE) with full FSM, JWT auth, reconnect/backoff, and OnDemandFetchCoordinator with CDN bypass; automatic fallback to polling.
 - Impression recorders in three modes: debug, optimized, none.
 - Dynamic configurations via WithConfig methods.
 - Input validation and limits enforced on evaluation and track paths.
 - Runs on all Dart targets: Dart VM, Flutter Android/iOS/Web/Desktop.
