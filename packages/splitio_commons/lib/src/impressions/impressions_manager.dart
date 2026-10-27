import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';

import 'impression_strategy.dart';

class ImpressionsManager {
  final ImpressionStrategy _strategy;
  final ImpressionListener? _listener;
  final ConsentStatus Function() _consentProvider;
  final SplitLogger _log;
  final String _sdkVersion;

  ImpressionsManager({
    required ImpressionStrategy strategy,
    ImpressionListener? listener,
    required ConsentStatus Function() consentProvider,
    required SplitLogger log,
    required String sdkVersion,
  })  : _strategy = strategy,
        _listener = listener,
        _consentProvider = consentProvider,
        _log = log,
        _sdkVersion = sdkVersion;

  void record(KeyImpression impression, bool impressionsDisabled,
      Attributes? attributes) {
    _fireListener(impression, attributes);

    final consent = _consentProvider();
    if (consent == ConsentStatus.declined) {
      _log.debug(
          'Impression dropped — consent declined [feature=${impression.feature}, key=${impression.keyName}]');
      return;
    }

    _log.verbose(
        'Recording impression [feature=${impression.feature}, key=${impression.keyName}, treatment=${impression.treatment}]');
    _strategy.process(impression);
  }

  void _fireListener(KeyImpression impression, Attributes? attributes) {
    final listener = _listener;
    if (listener == null) return;
    scheduleMicrotask(() {
      try {
        listener.logImpression(ImpressionData(
          feature: impression.feature,
          keyName: impression.keyName,
          bucketingKey: impression.bucketingKey,
          treatment: impression.treatment,
          label: impression.label,
          changeNumber: impression.changeNumber ?? 0,
          time: impression.time,
          pt: impression.pt,
          attributes: attributes,
          sdkLanguageVersion: _sdkVersion,
        ));
      } catch (_) {}
    });
  }
}
