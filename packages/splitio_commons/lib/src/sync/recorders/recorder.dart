import 'dart:async';

import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';

abstract class Recorder {
  final SplitHttpClient httpClient;
  final SplitLogger log;
  final String url;
  final int pushRateSeconds;
  Timer? _timer;

  Recorder({
    required this.httpClient,
    required this.log,
    required this.url,
    required this.pushRateSeconds,
  });

  Future<void> flush();

  /// Drops any batch retained for a retry by this recorder's
  /// `BatchSubmitter` (spec §7.2: consent DECLINED MUST drop queued data,
  /// including data already in flight for a retry — not just the live
  /// store). Subclasses that own a `BatchSubmitter` MUST override this to
  /// forward to its `clear()`. Default no-op for recorders with nothing to
  /// retain.
  void clearRetained() {}

  bool get isRunning => _timer != null;

  void start() {
    _timer = Timer.periodic(
      Duration(seconds: pushRateSeconds),
      (_) => flush(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
