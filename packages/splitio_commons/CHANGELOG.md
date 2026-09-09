2.0.0 (September 9, 2026)
 - BREAKING: `EvaluationContext` is no longer exported from the `splitio_commons` barrel. Import it from `package:splitio_commons/src/core/evaluation_context.dart` if you still need it, or remove the reference — it was intended as an internal SPI.
 - Fixed: targeting engine now returns the default treatment's dynamic configuration when evaluation short-circuits on prerequisites-not-met or traffic-allocation exclusion (notInSplit).

1.0.0 (August 28, 2026)
Initial release. Shared components for the Split Dart SDK. Features:
 - Pure targeting engine (rule-in / result-out) with EvaluationContext callback seam.
 - Full matcher catalog with attribute coercion and semver semantics.
 - Bucketing (murmur3_32) with algo, seed, and traffic-allocation gate.
 - Parsing pipeline: wire DTOs → ParsedSplit + TargetingRule.
 - Storage core: change-based rule/RBS/membership stores with in-memory impl and no-op PersistentStore SPI.
 - Sync engine: combined rules+rbs poll feed (dual cursor), per-key membership feed (MS + LS), OnDemandFetchCoordinator with CDN bypass.
 - Streaming state machine: 3-axis push gate, JWT auth cache/refresh, reconnect/backoff, notification processor for SPLIT_UPDATE/SPLIT_KILL/MEMBERSHIPS_*/RB_SEGMENT_UPDATE.
 - Recorders: impressions, impressions count, unique keys (CS set), events; queue → batch → flush.
 - Readiness/lifecycle manager with latched READY / READY_TIMEOUT and recurring UPDATE events.
 - HTTP client with retry/backoff and canonical query-param ordering for CDN cache stability.
 - Auth strategies: static SDK key and JWT (cached, deduped, on-demand).
 - Observer / internal event bus for pub/sub.
 - Logger abstraction over package:logging.
 - Single-isolate, lock-free consistency model; platform-agnostic (no dart:io / dart:html in shared code).
