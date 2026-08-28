import 'package:splitio_commons/src/core/core.dart' show murmurhash3X8632;

/// Membership fetch strategy for an instant-update notification (spec §12).
/// Only [unbounded] and [bounded] fetch notifications get a jitter delay;
/// [keyList] and [segmentRemoval] apply their payload immediately.
enum MembershipStrategy { unbounded, bounded, keyList, segmentRemoval }

/// `HashingAlgorithm` wire values (spec §12.3): `0 = NONE`, `1 = MURMUR3_32`.
class HashingAlgorithm {
  static const int none = 0;
  static const int murmur3_32 = 1;
}

/// Pure seed-based jitter (spec §12.3): spreads fetch load across clients by
/// delaying the on-demand fetch by a deterministic amount derived from the
/// user's key. Zero I/O; the caller schedules the delay via a `Scheduler`.
class SyncDelayCalculator {
  const SyncDelayCalculator();

  /// Computes the fetch delay in milliseconds, always in `[0, i)`.
  ///
  /// - `strategy` outside {unbounded, bounded} or `h == NONE` → `0`.
  /// - `i` (updateIntervalMs) null or `<= 0` → default `60000`.
  /// - `s` (algorithmSeed) null → `0`.
  /// - otherwise `murmurhash3X8632(key, seed=s) % i`.
  int delayMs({
    required String matchingKey,
    required MembershipStrategy strategy,
    int? i,
    int h = HashingAlgorithm.murmur3_32,
    int? s,
  }) {
    final isFetch = strategy == MembershipStrategy.unbounded ||
        strategy == MembershipStrategy.bounded;
    if (!isFetch || h == HashingAlgorithm.none) return 0;

    final interval = (i == null || i <= 0) ? 60000 : i;
    final seed = s ?? 0;
    final hash = murmurhash3X8632(matchingKey, seed) & 0xFFFFFFFF;
    final delay = hash % interval;
    return delay < 0 ? delay + interval : delay;
  }
}
