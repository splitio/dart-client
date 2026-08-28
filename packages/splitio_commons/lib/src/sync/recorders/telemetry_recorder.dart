import 'package:splitio_commons/src/sync/sync.dart';

/// Reserved seam for the telemetry recorder (§17.2). MUST NOT ship active
/// telemetry reporting in v1 — `flush()` is a no-op — but the `Recorder`
/// shape is declared now so a future implementation can land without core
/// surgery to `DependencyContainer` or `SyncManager`.
class TelemetryRecorder extends Recorder {
  TelemetryRecorder({
    required super.httpClient,
    required super.url,
    required super.log,
    super.pushRateSeconds = 3600,
  });

  @override
  Future<void> flush() async {}
}
