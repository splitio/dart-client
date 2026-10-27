import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';

/// Shared retry/submit policy for recorder POSTs (spec §13.1).
///
/// A POST that ends in a transient status (`429`/`5xx`, §10.3) or a
/// transport error is **not** silently dropped: the batch is retained and
/// retried once on the recorder's *next* flush cycle (not inline — the
/// caller's next [submit] call is what performs the retry). If that retry
/// also fails, the batch is dropped and a warning is logged with the data
/// type and item count. A non-retryable status (any other `4xx`) drops the
/// batch immediately, with a warning. Every failed attempt is logged.
///
/// One instance is owned per recorder and is stateful — it is the seam that
/// lets all four recorders (impressions, events, impression counts, unique
/// keys) share one retry implementation instead of four copies.
///
/// Retry status is decided once per flush cycle by [prependRetained]: in a
/// cycle that carries a retained batch, every failed chunk is dropped (as in
/// JS, fresh items merged into a retry share its fate); otherwise every
/// failed chunk of the cycle is retained, so a multi-chunk flush (500-item
/// batches) never loses an earlier failed chunk.
///
/// Source parity: `javascript-commons` `sync/submitters/submitter.ts`.
class BatchSubmitter<T> {
  final SplitLogger _log;
  final String _dataTypeName;

  final List<T> _retained = [];
  bool _cycleIsRetry = false;

  BatchSubmitter({required SplitLogger log, required String dataTypeName})
      : _log = log,
        _dataTypeName = dataTypeName;

  /// Prepends any batch retained from a previous failed [submit] onto
  /// [freshItems] and starts a new flush cycle. Callers MUST call this once
  /// before chunking/sending each flush cycle's data, so a pending retry
  /// rides along with new items.
  List<T> prependRetained(List<T> freshItems) {
    _cycleIsRetry = _retained.isNotEmpty;
    if (!_cycleIsRetry) return freshItems;
    final merged = [..._retained, ...freshItems];
    _retained.clear();
    return merged;
  }

  /// Sends [batch] via [send]. On a `2xx` response this returns normally.
  /// On failure: a transient status/transport error retains [batch] for one
  /// retry on the caller's next flush cycle, unless [batch] is itself
  /// already a retry — in which case (or on a non-retryable status) it is
  /// dropped, with a warning logged naming [T]'s data type and item count.
  Future<void> submit(
    List<T> batch,
    Future<SplitHttpResponse> Function() send,
  ) async {
    if (batch.isEmpty) return;
    try {
      final response = await send();
      if (response.statusCode >= 200 && response.statusCode < 300) return;
      _onFailure(
        batch,
        transient: classifyStatus(response.statusCode) ==
            HttpStatusAction.transientRetry,
        reason: 'HTTP ${response.statusCode}',
      );
    } catch (e) {
      _onFailure(batch, transient: true, reason: '$e');
    }
  }

  /// Drops any retained batch and resets retry state (spec §7.2: consent
  /// transitioning to DECLINED MUST drop queued data, including a batch
  /// retained from a previously failed flush — not just the live store).
  /// Callers MUST invoke this from their recorder's consent-declined clear
  /// path so a stale, pre-decline batch is never resent on the next flush.
  void clear() {
    _retained.clear();
    _cycleIsRetry = false;
  }

  void _onFailure(
    List<T> batch, {
    required bool transient,
    required String reason,
  }) {
    if (transient && !_cycleIsRetry) {
      _retained.addAll(batch);
      _log.warning('Failed to post $_dataTypeName (${batch.length} '
          'item(s)): $reason. Retaining for retry on next flush.');
      return;
    }
    _log.warning('Dropping $_dataTypeName batch (${batch.length} item(s)) '
        'after failed POST: $reason');
  }
}
