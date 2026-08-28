import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/impressions/impressions.dart';
import 'package:test/test.dart';

void main() {
  KeyImpression makeImpression({
    String feature = 'feat',
    String keyName = 'user1',
    String treatment = 'on',
    int changeNumber = 100,
    String label = 'rule',
    int time = 1000,
  }) {
    return KeyImpression(
      feature: feature,
      keyName: keyName,
      treatment: treatment,
      changeNumber: changeNumber,
      label: label,
      time: time,
    );
  }

  group('NoneImpressionStrategy', () {
    test('process calls counter and tracker', () {
      final counter = ImpressionsCounter();
      final tracker = UniqueKeysTracker();
      final strategy = NoneImpressionStrategy(
        counter: counter,
        tracker: tracker,
      );

      strategy.process(
          makeImpression(feature: 'feat', keyName: 'user1', time: 3600000));

      expect(counter.popAll(), isNotEmpty);
      expect(tracker.popAll()['feat'], contains('user1'));
    });

    test('process does not push to impressions store', () {
      final counter = ImpressionsCounter();
      final tracker = UniqueKeysTracker();
      final store = InMemoryImpressionsStore();
      final strategy = NoneImpressionStrategy(
        counter: counter,
        tracker: tracker,
      );

      strategy.process(makeImpression());

      expect(store.popAll(), isEmpty);
    });
  });

  group('DebugImpressionStrategy', () {
    test('always queues the impression', () {
      final observer = ImpressionsObserver();
      final store = InMemoryImpressionsStore();
      final strategy = DebugImpressionStrategy(
        observer: observer,
        store: store,
      );

      strategy.process(makeImpression());
      strategy.process(makeImpression());

      expect(store.popAll(), hasLength(2));
    });

    test('sets pt from observer on queued impression', () {
      final observer = ImpressionsObserver();
      final store = InMemoryImpressionsStore();
      final strategy = DebugImpressionStrategy(
        observer: observer,
        store: store,
      );

      strategy.process(makeImpression(time: 1000));
      strategy.process(makeImpression(time: 2000));

      final impressions = store.popAll();
      expect(impressions[0].pt, isNull);
      expect(impressions[1].pt, equals(1000));
    });

    test('queues duplicates (all impressions recorded)', () {
      final observer = ImpressionsObserver();
      final store = InMemoryImpressionsStore();
      final strategy = DebugImpressionStrategy(
        observer: observer,
        store: store,
      );

      strategy.process(makeImpression(time: 1000));
      strategy.process(makeImpression(time: 2000));
      strategy.process(makeImpression(time: 3000));

      expect(store.popAll(), hasLength(3));
    });
  });

  group('OptimizedImpressionStrategy', () {
    test('only queues first-seen impression (deduplicates)', () {
      final observer = ImpressionsObserver();
      final counter = ImpressionsCounter();
      final store = InMemoryImpressionsStore();
      final strategy = OptimizedImpressionStrategy(
        observer: observer,
        counter: counter,
        store: store,
      );

      strategy.process(makeImpression(time: 1000));
      strategy.process(makeImpression(time: 2000));

      expect(store.popAll(), hasLength(1));
    });

    test('queues different impressions', () {
      final observer = ImpressionsObserver();
      final counter = ImpressionsCounter();
      final store = InMemoryImpressionsStore();
      final strategy = OptimizedImpressionStrategy(
        observer: observer,
        counter: counter,
        store: store,
      );

      strategy.process(makeImpression(feature: 'a', time: 1000));
      strategy.process(makeImpression(feature: 'b', time: 2000));

      expect(store.popAll(), hasLength(2));
    });

    test('always records counts regardless of dedup', () {
      final observer = ImpressionsObserver();
      final counter = ImpressionsCounter();
      final store = InMemoryImpressionsStore();
      final strategy = OptimizedImpressionStrategy(
        observer: observer,
        counter: counter,
        store: store,
      );

      strategy.process(makeImpression(time: 3600000));
      strategy.process(makeImpression(time: 3600001));

      expect(counter.popAll()['feat::3600000'], equals(2));
    });

    test('counts recorded even when impression is deduplicated', () {
      final observer = ImpressionsObserver();
      final counter = ImpressionsCounter();
      final store = InMemoryImpressionsStore();
      final strategy = OptimizedImpressionStrategy(
        observer: observer,
        counter: counter,
        store: store,
      );

      strategy.process(makeImpression(time: 3600000));
      strategy.process(makeImpression(time: 3600500));
      strategy.process(makeImpression(time: 3600900));

      expect(store.popAll(), hasLength(1));
      expect(counter.popAll()['feat::3600000'], equals(3));
    });
  });
}
