import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';

abstract class Fetcher {
  final SplitHttpClient httpClient;
  final SplitLogger log;
  final String baseUrl;
  final int _maxRetries;
  final Duration _baseBackoff;

  Fetcher({
    required this.httpClient,
    required this.log,
    required this.baseUrl,
    int maxRetries = 3,
    Duration baseBackoff = const Duration(seconds: 1),
  })  : _maxRetries = maxRetries,
        _baseBackoff = baseBackoff;

  Future<bool> fetch();

  Future<T?> withRetry<T>(String name, Future<T> Function() operation) async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e, st) {
        log.error('Exception in $name (attempt ${attempt + 1}/$_maxRetries)',
            '$e\n$st');
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_baseBackoff * (1 << attempt));
        }
      }
    }
    return null;
  }
}
