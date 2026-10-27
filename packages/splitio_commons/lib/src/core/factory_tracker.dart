import 'package:splitio_commons/src/logger/logger.dart';

/// Process-wide count of live (not destroyed) factories per SDK key, used to
/// warn about duplicate factory instances (spec §7). Mirrors
/// `javascript-commons` `validateAndTrackApiKey` / `releaseApiKey`.
///
/// Only real factories are tracked; NoOp factories MUST NOT call [track].
class FactoryTracker {
  FactoryTracker._();

  static final Map<String, int> _liveBySdkKey = {};

  /// Registers a new live factory for [sdkKey] and logs a WARNING when another
  /// factory already exists (for the same key, or for a different key).
  static void track(String sdkKey, SplitLogger log) {
    final existing = _liveBySdkKey[sdkKey];
    if (existing == null || existing == 0) {
      _liveBySdkKey[sdkKey] = 1;
      if (_liveBySdkKey.length > 1) {
        log.warning(_message('an instance of the Split factory'));
      }
    } else {
      log.warning(_message('$existing factory/ies with this SDK Key'));
      _liveBySdkKey[sdkKey] = existing + 1;
    }
  }

  /// Decrements the live count for [sdkKey]. Callers MUST call it at most once
  /// per tracked factory (factory teardown runs once).
  static void release(String sdkKey) {
    final existing = _liveBySdkKey[sdkKey];
    if (existing == null) return;
    if (existing <= 1) {
      _liveBySdkKey.remove(sdkKey);
    } else {
      _liveBySdkKey[sdkKey] = existing - 1;
    }
  }

  /// Number of live factories for [sdkKey].
  static int liveCount(String sdkKey) => _liveBySdkKey[sdkKey] ?? 0;

  /// Clears all counts. Test-only: lets unit tests start from a clean slate.
  /// (Not annotated `@visibleForTesting` to avoid adding a `package:meta`
  /// dependency; do not call from production code.)
  static void resetForTesting() => _liveBySdkKey.clear();

  static String _message(String what) =>
      'settings: You already have $what. We recommend keeping '
      'only one instance of the factory at all times (Singleton pattern) and '
      'reusing it throughout your application';
}
