import 'dart:convert';

import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/sync/segment_sync_task.dart';

import 'fetcher.dart';

class MembershipsFetcher extends Fetcher implements SegmentSyncTask {
  final MembershipsProcessor _processor;
  final Set<String> _boundKeys = {};
  final void Function(String key, bool success)? _onKeyResult;
  final void Function(String key)? _onUpdate;

  MembershipsFetcher({
    required super.httpClient,
    required super.log,
    required super.baseUrl,
    super.maxRetries,
    super.baseBackoff,
    required MembershipsProcessor processor,
    void Function(String key, bool success)? onKeyResult,
    void Function(String key)? onUpdate,
  })  : _processor = processor,
        _onKeyResult = onKeyResult,
        _onUpdate = onUpdate;

  /// Reports that [key]'s membership changed via an in-place streaming
  /// apply (spec §12.2) rather than through [fetchForKey]'s own HTTP round
  /// trip — used by [MembershipFeedDispatcher] on the shared instance it
  /// holds (spec §4.6/§8.2).
  void notifyUpdate(String key) => _onUpdate?.call(key);

  Set<String> get boundKeys => Set.unmodifiable(_boundKeys);

  bool get hasBoundKeys => _boundKeys.isNotEmpty;

  void bindKey(String key) {
    _boundKeys.add(key);
  }

  @override
  Future<bool> fetch() async {
    if (_boundKeys.isEmpty) return false;
    final results = await Future.wait(_boundKeys.map(fetchForKey));
    return results.every((r) => r);
  }

  Future<bool> fetchForKey(String key) async {
    final result = await withRetry('MembershipsFetcher.fetch', () async {
      final url = '$baseUrl/memberships/${Uri.encodeComponent(key)}';

      if (log.isDebugEnabled) log.debug('GET $url');

      final response = await httpClient.get(
        url,
        extraHeaders: const {'Cache-Control': 'no-cache'},
      );

      if (log.isDebugEnabled) {
        log.debug('Memberships response: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        if (log.isVerboseEnabled) {
          log.verbose(
              'Memberships body (first 300): ${response.body.substring(0, response.body.length < 300 ? response.body.length : 300)}');
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final changed = _processor.processMemberships(data, key);
        if (changed) _onUpdate?.call(key);
        log.debug('Memberships applied for key: $key');
        return true;
      }
      logStatusFailure('Memberships fetch failed: ${response.statusCode}',
          response.statusCode);
      return false;
    });
    final success = result ?? false;
    // Covers the aggregate fetch() (polling/initial sync) AND streaming
    // catch-up (MembershipFeedDispatcher calls this same method on the
    // same shared instance), so readiness can be derived from whichever
    // path succeeds first (spec §8.2).
    _onKeyResult?.call(key, success);
    return success;
  }
}
