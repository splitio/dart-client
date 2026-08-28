import 'dart:async';

import 'package:splitio_commons/src/impressions/impressions_counter.dart';
import 'package:splitio_commons/src/models/enums.dart';
import 'package:splitio_commons/src/sync/sync.dart';

/// Posts per-feature hourly impression counts to POST /testImpressions/count.
/// Used in OPTIMIZED and NONE impressions modes (§13.2, §19.4).
class ImpressionsCountRecorder extends Recorder {
  final ImpressionsCounter _counter;
  final ConsentStatus Function() _consentProvider;

  ImpressionsCountRecorder({
    required ImpressionsCounter counter,
    required ConsentStatus Function() consentProvider,
    required super.httpClient,
    required super.url,
    required super.log,
  })  : _counter = counter,
        _consentProvider = consentProvider,
        super(pushRateSeconds: 1800);

  @override
  Future<void> flush() async {
    if (_consentProvider() == ConsentStatus.unknown) {
      log.debug('ImpressionsCountRecorder: flush skipped — consent unknown');
      return;
    }
    if (_counter.isEmpty) {
      log.verbose('ImpressionsCountRecorder: nothing to flush');
      return;
    }

    final counts = _counter.popAll();
    final pf = <Map<String, Object>>[];
    for (final entry in counts.entries) {
      final parts = entry.key.split('::');
      final feature = parts[0];
      final hourBucket = int.parse(parts[1]);
      pf.add({'f': feature, 'm': hourBucket, 'rc': entry.value});
    }

    log.debug(
        'ImpressionsCountRecorder: flushing ${pf.length} feature count(s)');
    final body = {'pf': pf};
    try {
      await httpClient.post('$url/testImpressions/count', body: body);
    } catch (e) {
      log.warning('Failed to post impressions count, retrying once: $e');
      try {
        await httpClient.post('$url/testImpressions/count', body: body);
      } catch (e) {
        log.error('Failed to post impressions count after retry: $e');
      }
    }
  }
}
