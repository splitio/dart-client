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
