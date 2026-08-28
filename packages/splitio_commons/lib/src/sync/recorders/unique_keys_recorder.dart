import 'dart:async';

import 'package:splitio_commons/src/impressions/unique_keys_tracker.dart';
import 'package:splitio_commons/src/models/enums.dart';
import 'package:splitio_commons/src/sync/sync.dart';

/// Posts unique matching keys per feature to POST /v1/keys/cs on the
/// telemetry host (§19.1). Used only in NONE impressions mode (§13.2, §19.4).
class UniqueKeysRecorder extends Recorder {
  final UniqueKeysTracker _tracker;
  final ConsentStatus Function() _consentProvider;

  UniqueKeysRecorder({
    required UniqueKeysTracker tracker,
    required ConsentStatus Function() consentProvider,
    required super.httpClient,
    required super.url,
    required super.log,
  })  : _tracker = tracker,
        _consentProvider = consentProvider,
        super(pushRateSeconds: 900);

  @override
  Future<void> flush() async {
    if (_consentProvider() == ConsentStatus.unknown) {
      log.debug('UniqueKeysRecorder: flush skipped — consent unknown');
      return;
    }
    if (_tracker.isEmpty) {
      log.verbose('UniqueKeysRecorder: nothing to flush');
      return;
    }

    final byFeature = _tracker.popAll();

    // Invert to key-centric: Map<matchingKey, Set<featureName>>
    final byKey = <String, Set<String>>{};
    for (final featureEntry in byFeature.entries) {
      for (final key in featureEntry.value) {
        byKey.putIfAbsent(key, () => {}).add(featureEntry.key);
      }
    }

    final keys = byKey.entries
        .map((e) => <String, Object>{'k': e.key, 'fs': e.value.toList()})
        .toList();

    log.debug('UniqueKeysRecorder: flushing ${keys.length} unique key(s)');
    try {
      await httpClient.post(
        '$url/v1/keys/cs',
        body: {'keys': keys},
      );
    } catch (e) {
      log.error('Failed to post unique keys: $e');
    }
  }
}
