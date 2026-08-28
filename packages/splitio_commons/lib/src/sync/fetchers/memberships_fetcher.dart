import 'dart:convert';

import 'package:splitio_commons/src/parsing/parsing.dart';

import 'fetcher.dart';

class MembershipsFetcher extends Fetcher {
  final MembershipsProcessor _processor;
  final Set<String> _boundKeys = {};

  MembershipsFetcher({
    required super.httpClient,
    required super.log,
    required super.baseUrl,
    super.maxRetries,
    super.baseBackoff,
    required MembershipsProcessor processor,
  }) : _processor = processor;

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
      final url = '$baseUrl/memberships/$key';

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
        _processor.processMemberships(data, key);
        log.debug('Memberships applied for key: $key');
        return true;
      }
      log.warning('Memberships fetch failed: ${response.statusCode}');
      return false;
    });
    return result ?? false;
  }
}
