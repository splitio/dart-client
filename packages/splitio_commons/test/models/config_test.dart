import 'package:splitio_commons/src/models/config.dart';
import 'package:test/test.dart';

void main() {
  group('ServiceEndpoints', () {
    test('resolved getters fall back to defaults when unset', () {
      const endpoints = ServiceEndpoints();

      expect(endpoints.resolvedSdkUrl, ServiceEndpoints.defaultSdkUrl);
      expect(endpoints.resolvedEventsUrl, ServiceEndpoints.defaultEventsUrl);
      expect(endpoints.resolvedAuthUrl, ServiceEndpoints.defaultAuthUrl);
      expect(
          endpoints.resolvedStreamingUrl, ServiceEndpoints.defaultStreamingUrl);
      expect(
          endpoints.resolvedTelemetryUrl, ServiceEndpoints.defaultTelemetryUrl);
    });

    test('resolved getters prefer explicit overrides', () {
      const endpoints = ServiceEndpoints(
        sdkUrl: 'https://sdk.custom.io',
        eventsUrl: 'https://events.custom.io',
        authUrl: 'https://auth.custom.io',
        streamingUrl: 'https://streaming.custom.io',
        telemetryUrl: 'https://telemetry.custom.io',
      );

      expect(endpoints.resolvedSdkUrl, 'https://sdk.custom.io');
      expect(endpoints.resolvedEventsUrl, 'https://events.custom.io');
      expect(endpoints.resolvedAuthUrl, 'https://auth.custom.io');
      expect(endpoints.resolvedStreamingUrl, 'https://streaming.custom.io');
      expect(endpoints.resolvedTelemetryUrl, 'https://telemetry.custom.io');
    });
  });
}
