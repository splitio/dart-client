import 'enums.dart';
import 'log_level.dart';

/// Default and overridable base URLs for Split's server-side APIs.
///
/// Add a new endpoint here — a field, a `defaultXUrl` constant, and a
/// `resolvedXUrl` getter — and it's usable everywhere (SDK sync, streaming,
/// and any future server-side consumer of this shared package) with no
/// other changes needed.
final class ServiceEndpoints {
  static const String defaultSdkUrl = 'https://sdk.split.io/api';
  static const String defaultEventsUrl = 'https://events.split.io/api';
  static const String defaultAuthUrl = 'https://auth.split.io/api';
  static const String defaultStreamingUrl = 'https://streaming.split.io';
  static const String defaultTelemetryUrl = 'https://telemetry.split.io/api';

  final String? sdkUrl;
  final String? eventsUrl;
  final String? authUrl;
  final String? streamingUrl;
  final String? telemetryUrl;

  const ServiceEndpoints({
    this.sdkUrl,
    this.eventsUrl,
    this.authUrl,
    this.streamingUrl,
    this.telemetryUrl,
  });

  String get resolvedSdkUrl => sdkUrl ?? defaultSdkUrl;
  String get resolvedEventsUrl => eventsUrl ?? defaultEventsUrl;
  String get resolvedAuthUrl => authUrl ?? defaultAuthUrl;
  String get resolvedStreamingUrl => streamingUrl ?? defaultStreamingUrl;
  String get resolvedTelemetryUrl => telemetryUrl ?? defaultTelemetryUrl;
}

final class SyncConfig {
  final int featureFlagsPollingRate;
  final int segmentsPollingRate;
  final int impressionsPushRate;
  final int eventsPushRate;
  final int readyTimeout;
  final ServiceEndpoints? serviceEndpoints;
  final bool streamingEnabled;

  const SyncConfig({
    this.featureFlagsPollingRate = 60,
    this.segmentsPollingRate = 60,
    this.impressionsPushRate = 300,
    this.eventsPushRate = 60,
    this.readyTimeout = 10,
    this.serviceEndpoints,
    this.streamingEnabled = true,
  });

  static const int _defaultFeatureFlagsPollingRate = 60;
  static const int _defaultSegmentsPollingRate = 60;
  static const int _defaultImpressionsPushRate = 300;
  static const int _defaultEventsPushRate = 60;

  /// Minimum polling/push rate (seconds) enforced on the server-side flavor.
  static const int serverSideMinRate = 30;

  /// Returns a copy with the rates normalized per flavor (spec §19.4).
  ///
  /// - [serverSide] `true` (default): every rate below [serverSideMinRate] is
  ///   raised to it, and [onWarning] receives a message naming each clamped
  ///   setting.
  /// - [serverSide] `false` (client-side): positive rates are kept as-is (no
  ///   minimum, JS parity); non-positive rates fall back to their default.
  SyncConfig normalized({
    bool serverSide = true,
    void Function(String message)? onWarning,
  }) {
    int rate(String name, int value, int fallback) {
      if (!serverSide) return value > 0 ? value : fallback;
      if (value >= serverSideMinRate) return value;
      onWarning?.call('$name $value is below the minimum of '
          '$serverSideMinRate seconds; using $serverSideMinRate.');
      return serverSideMinRate;
    }

    return SyncConfig(
      featureFlagsPollingRate: rate('featureFlagsPollingRate',
          featureFlagsPollingRate, _defaultFeatureFlagsPollingRate),
      segmentsPollingRate: rate('segmentsPollingRate', segmentsPollingRate,
          _defaultSegmentsPollingRate),
      impressionsPushRate: rate('impressionsPushRate', impressionsPushRate,
          _defaultImpressionsPushRate),
      eventsPushRate:
          rate('eventsPushRate', eventsPushRate, _defaultEventsPushRate),
      readyTimeout: readyTimeout < 0 ? 0 : readyTimeout,
      serviceEndpoints: serviceEndpoints,
      streamingEnabled: streamingEnabled,
    );
  }
}

abstract class ImpressionListener {
  void logImpression(ImpressionData data);
}

final class ImpressionData {
  final String feature;
  final String keyName;
  final String? bucketingKey;
  final String treatment;
  final String label;
  final int changeNumber;
  final int time;
  final int? pt;
  final Map<String, Object?>? attributes;
  final String sdkLanguageVersion;

  const ImpressionData({
    required this.feature,
    required this.keyName,
    this.bucketingKey,
    required this.treatment,
    required this.label,
    required this.changeNumber,
    required this.time,
    this.pt,
    this.attributes,
    required this.sdkLanguageVersion,
  });
}

final class SplitClientConfig {
  final SyncConfig sync;
  final ImpressionsMode impressionsMode;
  final ConsentStatus userConsent;
  final ImpressionListener? impressionListener;

  /// SDK log verbosity. Defaults to [LogLevel.none] (silent, spec §14).
  final LogLevel logLevel;
  final bool installSignalHandler;

  const SplitClientConfig({
    this.sync = const SyncConfig(),
    this.impressionsMode = ImpressionsMode.optimized,
    this.userConsent = ConsentStatus.granted,
    this.impressionListener,
    this.logLevel = LogLevel.none,
    this.installSignalHandler = true,
  });
}
