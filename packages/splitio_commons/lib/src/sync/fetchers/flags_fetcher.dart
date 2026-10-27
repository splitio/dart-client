import 'dart:convert';

import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';

import 'fetcher.dart';

class FlagsFetcher extends Fetcher {
  final SplitChangeProcessor _processor;
  final Store<ParsedSplit> _ruleStore;
  final Store<RuleBasedSegment> _rbsStore;
  final void Function(List<String> changedFlags)? _onUpdate;
  final void Function(bool success)? _onResult;

  FlagsFetcher({
    required super.httpClient,
    required super.log,
    required super.baseUrl,
    super.maxRetries,
    super.baseBackoff,
    required SplitChangeProcessor processor,
    required Store<ParsedSplit> ruleStore,
    required Store<RuleBasedSegment> rbsStore,
    void Function(List<String> changedFlags)? onUpdate,
    void Function(bool success)? onResult,
  })  : _processor = processor,
        _ruleStore = ruleStore,
        _rbsStore = rbsStore,
        _onUpdate = onUpdate,
        _onResult = onResult;

  @override
  Future<bool> fetch() => fetchWithOptions();

  /// Fetches `/splitChanges`. [noCache] forces `Cache-Control: no-cache` —
  /// spec §10.2 requires this on a streaming-notification-triggered attempt
  /// (and its CDN-bypass fetch), and requires it be ABSENT on periodic polls,
  /// the initial sync, and the push-up catch-up fetch (all of which call the
  /// plain [fetch] above, which defaults [noCache] to `false`). [till] is
  /// appended as the final query parameter — canonical order
  /// `s`→`since`→`rbSince`→`till` (spec §10.4) — only on a CDN-bypass attempt.
  Future<bool> fetchWithOptions({bool noCache = false, int? till}) async {
    final result = await withRetry('FlagsFetcher.fetch', () async {
      final since = _ruleStore.changeNumber();
      final rbSince = _rbsStore.changeNumber();

      final url = '$baseUrl/splitChanges';
      final params = <String, String>{
        's': '1.3',
        'since': since.toString(),
        'rbSince': rbSince.toString(),
        if (till != null) 'till': till.toString(),
      };

      if (log.isDebugEnabled) {
        log.debug(
            'GET $url?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}');
      }

      final response = await httpClient.get(
        url,
        queryParameters: params,
        extraHeaders: noCache ? const {'Cache-Control': 'no-cache'} : null,
      );

      if (log.isDebugEnabled) {
        log.debug('Response: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        if (log.isVerboseEnabled) {
          log.verbose(
              'Body (first 500): ${response.body.substring(0, response.body.length < 500 ? response.body.length : 500)}');
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final processResult = _processor.processTargetingRules(data);
        log.info(
            'Parsed ${processResult.changedFlags.length} flag changes, ff cursor: ${processResult.ffTill}, rbs cursor: ${processResult.rbsTill}');
        if (processResult.changedFlags.isNotEmpty || processResult.rbsChanged) {
          _onUpdate?.call(processResult.changedFlags);
        }
        return true;
      } else if (response.statusCode == 304) {
        log.debug('304 Not Modified');
        return true;
      }
      logStatusFailure(
          'Unexpected status ${response.statusCode}: ${response.body.substring(0, response.body.length < 200 ? response.body.length : 200)}',
          response.statusCode);
      return false;
    });
    final success = result ?? false;
    // Reports every sync attempt — including a late, successful poll or
    // streaming catch-up after a failed initial sync — so readiness can be
    // derived from whichever path actually succeeds first (spec §8.2).
    _onResult?.call(success);
    return success;
  }
}
