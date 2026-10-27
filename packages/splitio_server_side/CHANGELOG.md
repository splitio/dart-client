1.0.0 (October 27, 2026)
Initial release of the Split Dart server-side SDK (Dart VM only). Features:
 - `SplitFactory` with a single `ServerSplitClient`; the key is passed on every call.
 - getTreatment / getTreatments / getTreatmentsByFlagSets and their WithConfig variants, plus track.
 - `SplitManager` with split(), splits() and names().
 - Polling and streaming sync of feature flags and segments, with fallback to polling.
 - Impressions in debug, optimized or none mode.
 - Impressions and events flushed automatically on SIGTERM / SIGINT.
