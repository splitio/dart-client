import 'dart:async';

import 'package:splitio_commons/src/impressions/unique_keys_tracker.dart';
import 'package:splitio_commons/src/models/enums.dart';
import 'package:splitio_commons/src/sync/sync.dart';

import 'batch_submitter.dart';

/// Posts unique matching keys seen per feature to the telemetry host
/// (§19.1). Used only in NONE impressions mode (§13.2, §19.4). The wire
/// shape depends on [payloadFormat] (§19.6):
///  - `clientSide` (default) posts `POST /v1/keys/cs` grouped by matching
///    key: `{"keys":[{"k":"key","fs":["feature1","feature2"]}]}`.
///  - `serverSide` posts `POST /v1/keys/ss` grouped by feature:
///    `{"keys":[{"f":"feature_name","ks":["key1","key2"]}]}`.
class UniqueKeysRecorder extends Recorder {
  final UniqueKeysTracker _tracker;
  final ConsentStatus Function() _consentProvider;
  final UniqueKeysPayloadFormat _payloadFormat;
  final BatchSubmitter<MapEntry<String, Set<String>>> _submitter;

  UniqueKeysRecorder({
    required UniqueKeysTracker tracker,
    required ConsentStatus Function() consentProvider,
    UniqueKeysPayloadFormat payloadFormat = UniqueKeysPayloadFormat.clientSide,
    required super.httpClient,
    required super.url,
    required super.log,
  })  : _tracker = tracker,
        _consentProvider = consentProvider,
        _payloadFormat = payloadFormat,
        _submitter = BatchSubmitter(log: log, dataTypeName: 'unique keys'),
        super(pushRateSeconds: 900);

  bool get _isServerSide =>
      _payloadFormat == UniqueKeysPayloadFormat.serverSide;

  @override
  void clearRetained() => _submitter.clear();

  @override
  Future<void> flush() async {
    if (_consentProvider() == ConsentStatus.unknown) {
      log.debug('UniqueKeysRecorder: flush skipped — consent unknown');
      return;
    }

    // Tracker is already feature-centric: Map<featureName, Set<matchingKey>>.
    // That is exactly the server-side grouping; the client-side shape
    // inverts it to key-centric: Map<matchingKey, Set<featureName>>.
    final byFeature = _tracker.popAll();
    final grouped = _isServerSide ? byFeature : _invert(byFeature);

    final entries = _submitter.prependRetained(grouped.entries.toList());
    if (entries.isEmpty) {
      log.verbose('UniqueKeysRecorder: nothing to flush');
      return;
    }

    final keys = _isServerSide
        ? entries
            .map((e) => <String, Object>{'f': e.key, 'ks': e.value.toList()})
            .toList()
        : entries
            .map((e) => <String, Object>{'k': e.key, 'fs': e.value.toList()})
            .toList();
    final path = _isServerSide ? '/v1/keys/ss' : '/v1/keys/cs';

    log.debug('UniqueKeysRecorder: flushing ${keys.length} unique key(s)');
    await _submitter.submit(
      entries,
      () => httpClient.post('$url$path', body: {'keys': keys}),
    );
  }

  static Map<String, Set<String>> _invert(Map<String, Set<String>> byFeature) {
    final byKey = <String, Set<String>>{};
    for (final featureEntry in byFeature.entries) {
      for (final key in featureEntry.value) {
        byKey.putIfAbsent(key, () => {}).add(featureEntry.key);
      }
    }
    return byKey;
  }
}
