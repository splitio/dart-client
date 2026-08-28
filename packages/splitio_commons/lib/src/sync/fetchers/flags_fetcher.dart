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
  })  : _processor = processor,
        _ruleStore = ruleStore,
        _rbsStore = rbsStore,
        _onUpdate = onUpdate;

  @override
  Future<bool> fetch() async {
    final result = await withRetry('FlagsFetcher.fetch', () async {
      final since = _ruleStore.changeNumber();
      final rbSince = _rbsStore.changeNumber();

      final url = '$baseUrl/splitChanges';
      final params = <String, String>{
        's': '1.3',
        'since': since.toString(),
        'rbSince': rbSince.toString(),
      };

      if (log.isDebugEnabled) {
        log.debug(
            'GET $url?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}');
      }

      final response = await httpClient.get(
        url,
        queryParameters: params,
        extraHeaders: const {'Cache-Control': 'no-cache'},
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
        if (processResult.changedFlags.isNotEmpty) {
          _onUpdate?.call(processResult.changedFlags);
        }
        return true;
      } else if (response.statusCode == 304) {
        log.debug('304 Not Modified');
        return true;
      }
      log.warning(
          'Unexpected status ${response.statusCode}: ${response.body.substring(0, response.body.length < 200 ? response.body.length : 200)}');
      return false;
    });
    return result ?? false;
  }
}
