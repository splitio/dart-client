/// Flavor-specific polling half of the sync layer (spec §8.4, §10). The
/// sync coordinator decides *when* to poll; implementations decide *what*.
abstract interface class PollingManager {
  /// Fetches every feed once (spec §8.1). Returns true only if all succeed.
  /// MUST NOT throw.
  Future<bool> syncAll();

  /// Arms the periodic timers. Idempotent while running.
  void start();

  /// Cancels every timer. Idempotent.
  void stop();

  /// True between [start] and [stop].
  bool get isRunning;
}
