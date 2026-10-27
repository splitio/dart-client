import 'dart:async';

import 'package:splitio_commons/src/impressions/impressions_counter.dart';
import 'package:splitio_commons/src/models/enums.dart';
import 'package:splitio_commons/src/sync/sync.dart';

import 'batch_submitter.dart';

/// Posts per-feature hourly impression counts to POST /testImpressions/count.
/// Used in OPTIMIZED and NONE impressions modes (§13.2, §19.4).
class ImpressionsCountRecorder extends Recorder {
  final ImpressionsCounter _counter;
  final ConsentStatus Function() _consentProvider;
  final BatchSubmitter<MapEntry<String, int>> _submitter;

  ImpressionsCountRecorder({
    required ImpressionsCounter counter,
    required ConsentStatus Function() consentProvider,
    required super.httpClient,
    required super.url,
    required super.log,
  })  : _counter = counter,
        _consentProvider = consentProvider,
        _submitter =
            BatchSubmitter(log: log, dataTypeName: 'impression counts'),
        super(pushRateSeconds: 1800);

  @override
  void clearRetained() => _submitter.clear();

  @override
  Future<void> flush() async {
    if (_consentProvider() == ConsentStatus.unknown) {
      log.debug('ImpressionsCountRecorder: flush skipped — consent unknown');
      return;
    }

    final counts =
        _submitter.prependRetained(_counter.popAll().entries.toList());
    if (counts.isEmpty) {
      log.verbose('ImpressionsCountRecorder: nothing to flush');
      return;
    }

    final pf = <Map<String, Object>>[];
    for (final entry in counts) {
      final parts = entry.key.split('::');
      final feature = parts[0];
      final hourBucket = int.parse(parts[1]);
      pf.add({'f': feature, 'm': hourBucket, 'rc': entry.value});
    }

    log.debug(
        'ImpressionsCountRecorder: flushing ${pf.length} feature count(s)');
    await _submitter.submit(
      counts,
      () => httpClient.post('$url/testImpressions/count', body: {'pf': pf}),
    );
  }
}
