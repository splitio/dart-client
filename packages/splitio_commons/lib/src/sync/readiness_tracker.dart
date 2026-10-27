/// Tracks readiness across one or more independently-synced feeds (e.g.
/// `"flags"`, `"segments"`, `"memberships"`). Fires [onSynced] exactly once —
/// the first time every feed in [requiredFeeds] has reported at least one
/// successful sync — regardless of which sync path produced that success
/// (initial sync, a periodic poll, or a streaming catch-up fetch).
///
/// This mirrors spec §8.2: a failed initial sync MUST NOT prevent READY from
/// firing later. Callers report every sync attempt via [markSynced]; this
/// class is the single place that decides whether the readiness condition
/// now holds.
class ReadinessTracker {
  final Set<String> _requiredFeeds;
  final Set<String> _syncedFeeds = {};
  final void Function() _onSynced;
  bool _fired = false;

  ReadinessTracker({
    required Set<String> requiredFeeds,
    required void Function() onSynced,
  })  : _requiredFeeds = requiredFeeds,
        _onSynced = onSynced;

  /// Records the outcome of a sync attempt for [feed].
  ///
  /// A `false` [success] is a no-op: it never un-marks a feed that
  /// previously synced successfully, and never fires [onSynced] on its own.
  /// Once [onSynced] has fired, further calls are no-ops — the tracker
  /// latches, matching the idempotency of `EventsManager.notifyReady()`.
  void markSynced(String feed, bool success) {
    if (_fired || !success) return;
    if (!_requiredFeeds.contains(feed)) return;
    _syncedFeeds.add(feed);
    if (_syncedFeeds.length >= _requiredFeeds.length) {
      _fired = true;
      _onSynced();
    }
  }
}
