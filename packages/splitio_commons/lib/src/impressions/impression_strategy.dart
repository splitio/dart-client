import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';

import 'impressions_counter.dart';
import 'impressions_observer.dart';
import 'unique_keys_tracker.dart';

abstract class ImpressionStrategy {
  void process(KeyImpression impression);
}

class NoneImpressionStrategy implements ImpressionStrategy {
  final ImpressionsCounter _counter;
  final UniqueKeysTracker _tracker;

  NoneImpressionStrategy({
    required ImpressionsCounter counter,
    required UniqueKeysTracker tracker,
  })  : _counter = counter,
        _tracker = tracker;

  @override
  void process(KeyImpression impression) {
    _counter.record(impression.feature, impression.time);
    _tracker.track(impression.feature, impression.keyName);
  }
}

class DebugImpressionStrategy implements ImpressionStrategy {
  final ImpressionsObserver _observer;
  final ImpressionsStore _store;

  DebugImpressionStrategy({
    required ImpressionsObserver observer,
    required ImpressionsStore store,
  })  : _observer = observer,
        _store = store;

  @override
  void process(KeyImpression impression) {
    impression.pt = _observer.testAndSet(
      impression.feature,
      impression.keyName,
      impression.treatment,
      impression.changeNumber,
      impression.label,
      impression.time,
    );

    _store.push(impression);
  }
}

class OptimizedImpressionStrategy implements ImpressionStrategy {
  final ImpressionsObserver _observer;
  final ImpressionsCounter _counter;
  final ImpressionsStore _store;

  OptimizedImpressionStrategy({
    required ImpressionsObserver observer,
    required ImpressionsCounter counter,
    required ImpressionsStore store,
  })  : _observer = observer,
        _counter = counter,
        _store = store;

  @override
  void process(KeyImpression impression) {
    final pt = _observer.testAndSet(
      impression.feature,
      impression.keyName,
      impression.treatment,
      impression.changeNumber,
      impression.label,
      impression.time,
    );
    if (pt == null) {
      _store.push(impression);
    }
    _counter.record(impression.feature, impression.time);
  }
}
