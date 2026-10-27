import 'dart:convert';

import 'package:splitio_commons/src/parsing/segment_change_processor.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/segment_sync_task.dart';

import 'fetcher.dart';

/// Server-side segment refresh loop. For every segment registered in the
/// [SegmentStore], polls `GET /segmentChanges/{name}?since=<cursor>` in a
/// greedy loop until the segment is caught up (`since === till`).
///
/// Server-side analog of [MembershipsFetcher]: same seam ([SegmentSyncTask]),
/// different endpoint shape (segment-scoped cursor vs per-key blob).
class SegmentChangesFetcher extends Fetcher implements SegmentSyncTask {
  final SegmentChangeProcessor _processor;
  final SegmentStore _store;
  final void Function(bool success)? _onResult;
  final void Function()? _onUpdate;

  // Guards against concurrent callers of fetch() (e.g. PollingManagerSS's
  // initial sync/polling, FlagsSegmentSync's immediate post-flags-change
  // trigger, and StreamingManager's catch-up — all share this one instance)
  // issuing duplicate `/segmentChanges` requests for the same segments at
  // the same cursor. A fetch() call made while one is already running
  // reuses that in-flight Future instead of starting a second HTTP
  // round-trip — but only when the segments it needs are already covered
  // by the one in flight; see [fetch] for why that distinction matters.
  Future<bool>? _inFlightFetch;
  Set<String>? _inFlightSegments;

  SegmentChangesFetcher({
    required super.httpClient,
    required super.log,
    required super.baseUrl,
    super.maxRetries,
    super.baseBackoff,
    required SegmentChangeProcessor processor,
    required SegmentStore store,
    void Function(bool success)? onResult,
    void Function()? onUpdate,
  })  : _processor = processor,
        _store = store,
        _onResult = onResult,
        _onUpdate = onUpdate;

  @override
  Future<bool> fetch() {
    final currentSegments = _store.getRegisteredSegments().toSet();
    final inFlight = _inFlightFetch;
    final inFlightSegments = _inFlightSegments;
    if (inFlight != null &&
        inFlightSegments != null &&
        currentSegments.every(inFlightSegments.contains)) {
      // Every segment this call needs is already covered by the running
      // fetch's snapshot — reuse it instead of a redundant HTTP round-trip.
      return inFlight;
    }
    if (inFlight != null) {
      // A segment was registered after the in-flight fetch's snapshot was
      // taken, so that call will never cover it. Wait for it to finish,
      // then issue a fresh fetch — otherwise the new segment would sit
      // unfetched until the next poll tick (defeating the immediate-fetch
      // fix in FlagsSegmentSync).
      return inFlight.then((_) => fetch());
    }
    final future = _runFetch(currentSegments);
    _inFlightFetch = future;
    _inFlightSegments = currentSegments;
    // Clearing must happen via a callback on `future`, not a `finally`
    // inside `_runFetch` — when `_runFetch` resolves synchronously (the
    // `segments.isEmpty` branch has no `await`), a `finally` there would
    // run and null the field BEFORE this very assignment above even
    // happens, permanently stuck non-null. `whenComplete` is always
    // deferred to a later microtask, even on an already-completed Future,
    // so this ordering is safe.
    future.whenComplete(() {
      if (identical(_inFlightFetch, future)) {
        _inFlightFetch = null;
        _inFlightSegments = null;
      }
    });
    return future;
  }

  Future<bool> _runFetch(Set<String> segments) async {
    bool success;
    if (segments.isEmpty) {
      success = true;
    } else {
      final results = await Future.wait(segments.map(fetchForSegment));
      success = results.every((r) => r);
    }
    // Covers both PollingManagerSS's polling/initial-sync call AND
    // StreamingManager's catch-up call — both invoke this same shared
    // instance's fetch(), so readiness can be derived from whichever path
    // succeeds first (spec §8.2).
    _onResult?.call(success);
    return success;
  }

  /// Fetches `GET /segmentChanges/[name]`, looping until caught up.
  /// [noCache]/[till] follow the same spec §10.2/§10.4 contract as
  /// [FlagsFetcher.fetchWithOptions]: both default to the plain polling/
  /// catch-up shape (no header, no `till`) used by [fetch] and the
  /// zero-arg callers wired as `segmentFetcher`/`allSegmentsFetcher`.
  Future<bool> fetchForSegment(
    String name, {
    bool noCache = false,
    int? till,
  }) async {
    var changed = false;
    final result =
        await withRetry('SegmentChangesFetcher.fetch[$name]', () async {
      var since = _store.changeNumber(name);
      while (true) {
        final url = '$baseUrl/segmentChanges/$name';
        final params = <String, String>{
          'since': since.toString(),
          if (till != null) 'till': till.toString(),
        };

        if (log.isDebugEnabled) log.debug('GET $url?since=$since');

        final response = await httpClient.get(
          url,
          queryParameters: params,
          extraHeaders: noCache ? const {'Cache-Control': 'no-cache'} : null,
        );

        if (response.statusCode != 200) {
          logStatusFailure(
              'SegmentChanges[$name] fetch failed: ${response.statusCode}',
              response.statusCode);
          return false;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final processed = _processor.processSegmentChange(data);
        if (processed == null) {
          log.warning('SegmentChanges[$name] malformed payload');
          return false;
        }
        changed = changed || processed.changed;

        if (processed.till == since) {
          // Caught up. Fire at most once per fetchForSegment call —
          // whenUpdated() consumers care that *a* change landed, not how
          // many internal HTTP round-trips this loop took to converge
          // (spec §4.6/§8.2).
          if (changed) _onUpdate?.call();
          return true;
        }
        since = processed.till;
      }
    });
    return result ?? false;
  }
}
