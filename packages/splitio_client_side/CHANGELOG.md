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
 - Impression recorders in three modes: debug, optimized, none; per-flag impressionsDisabled honored.
 - Dynamic configurations via WithConfig methods.
 - Input validation and limits enforced on evaluation and track paths.
 - Runs on all Dart targets: Dart VM, Flutter Android/iOS/Web/Desktop.
