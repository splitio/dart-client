import 'dart:async';

import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/sync.dart';

class ImpressionsRecorder extends Recorder {
  static const int _batchSize = 500;

  final ImpressionsStore _store;
  final ImpressionsMode _mode;

  ImpressionsRecorder({
    required ImpressionsStore store,
    required ImpressionsMode mode,
    required super.httpClient,
    required super.url,
    required super.pushRateSeconds,
    required super.log,
  })  : _store = store,
        _mode = mode;

  Future<void> flush() async {
    final impressions = _store.popAll();
    if (impressions.isEmpty) {
      log.verbose('ImpressionsRecorder: nothing to flush');
      return;
    }
    log.debug(
        'ImpressionsRecorder: flushing ${impressions.length} impression(s)');

    for (var i = 0; i < impressions.length; i += _batchSize) {
      final end = i + _batchSize > impressions.length
          ? impressions.length
          : i + _batchSize;
      final batch = impressions.sublist(i, end);
      final payload = _groupByFeature(batch);
      try {
        await httpClient.post(
          '$url/testImpressions/bulk',
          body: payload,
          extraHeaders: {
            'SplitSDKImpressionsMode': _mode.name.toUpperCase(),
          },
        );
      } catch (e) {
        log.error('Failed to post impressions batch: $e');
      }
    }
  }

  List<Map<String, Object?>> _groupByFeature(List<KeyImpression> impressions) {
    final Map<String, List<Map<String, Object?>>> grouped = {};
    for (final imp in impressions) {
      grouped.putIfAbsent(imp.feature, () => []);
      grouped[imp.feature]!.add({
        'k': imp.keyName,
        't': imp.treatment,
        'm': imp.time,
        'c': imp.changeNumber,
        'r': imp.label,
        if (imp.bucketingKey != null) 'b': imp.bucketingKey,
        if (imp.pt != null) 'pt': imp.pt,
      });
    }
    return grouped.entries
        .map((e) => <String, Object?>{'f': e.key, 'i': e.value})
        .toList();
  }
}
