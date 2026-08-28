import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/impressions/impressions.dart';
import 'package:test/test.dart';

class _FakeListener implements ImpressionListener {
  final List<ImpressionData> logged = [];
  bool shouldThrow = false;

  @override
  void logImpression(ImpressionData data) {
    if (shouldThrow) throw Exception('listener error');
    logged.add(data);
  }
}

void main() {
  group('ImpressionsObserver', () {
    late ImpressionsObserver observer;

    setUp(() {
      observer = ImpressionsObserver();
    });

    test('first call for a key returns null', () {
      final result =
          observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 1000);
      expect(result, isNull);
    });

    test('second call with same dedup key returns previous time', () {
      observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 1000);
      final result =
          observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 2000);
      expect(result, equals(1000));
    });

    test('third call returns the most recent previous time', () {
      observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 1000);
      observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 2000);
      final result =
          observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 3000);
      expect(result, equals(2000));
    });

    test('different feature returns null', () {
      observer.testAndSet('feat_a', 'user1', 'on', 100, 'rule', 1000);
      final result =
          observer.testAndSet('feat_b', 'user1', 'on', 100, 'rule', 2000);
      expect(result, isNull);
    });

    test('different key returns null', () {
      observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 1000);
      final result =
          observer.testAndSet('feat', 'user2', 'on', 100, 'rule', 2000);
      expect(result, isNull);
    });

    test('different treatment returns null', () {
      observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 1000);
      final result =
          observer.testAndSet('feat', 'user1', 'off', 100, 'rule', 2000);
      expect(result, isNull);
    });

    test('different changeNumber returns null', () {
      observer.testAndSet('feat', 'user1', 'on', 100, 'rule', 1000);
      final result =
          observer.testAndSet('feat', 'user1', 'on', 200, 'rule', 2000);
      expect(result, isNull);
    });

    test('LRU eviction removes oldest entries beyond max 500', () {
      for (var i = 0; i < 500; i++) {
        observer.testAndSet('feat_$i', 'user', 'on', 1, 'rule', i);
      }

      final beforeEviction =
          observer.testAndSet('feat_0', 'user', 'on', 1, 'rule', 999);
      expect(beforeEviction, equals(0));

      observer.testAndSet('feat_new', 'user', 'on', 1, 'rule', 5000);

      final afterEviction =
          observer.testAndSet('feat_1', 'user', 'on', 1, 'rule', 6000);
      expect(afterEviction, isNull);
    });
  });

  group('ImpressionsCounter', () {
    late ImpressionsCounter counter;

    setUp(() {
      counter = ImpressionsCounter();
    });

    test('isEmpty returns true initially', () {
      expect(counter.isEmpty, isTrue);
    });

    test('records count per feature and hour bucket', () {
      counter.record('feat_a', 3600000);
      counter.record('feat_a', 3600001);
      counter.record('feat_a', 3600999);

      final counts = counter.popAll();
      expect(counts['feat_a::3600000'], equals(3));
    });

    test('different features tracked separately', () {
      counter.record('feat_a', 3600000);
      counter.record('feat_b', 3600000);

      final counts = counter.popAll();
      expect(counts['feat_a::3600000'], equals(1));
      expect(counts['feat_b::3600000'], equals(1));
    });

    test('different hour buckets tracked separately', () {
      counter.record('feat_a', 3600000);
      counter.record('feat_a', 7200000);

      final counts = counter.popAll();
      expect(counts['feat_a::3600000'], equals(1));
      expect(counts['feat_a::7200000'], equals(1));
    });

    test('popAll clears internal state', () {
      counter.record('feat_a', 3600000);
      counter.popAll();

      expect(counter.isEmpty, isTrue);
      final counts = counter.popAll();
      expect(counts, isEmpty);
    });

    test('isEmpty returns false after recording', () {
      counter.record('feat_a', 1000);
      expect(counter.isEmpty, isFalse);
    });

    test('truncates timestamp to hour boundary', () {
      counter.record('feat', 5400000);
      final counts = counter.popAll();
      expect(counts.containsKey('feat::3600000'), isTrue);
    });
  });

  group('ImpressionsManager', () {
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

    ({ImpressionsManager manager, InMemoryImpressionsStore store}) makeManager({
      required ImpressionsMode mode,
      ImpressionListener? listener,
      ConsentStatus Function() consentProvider = _grantedConsent,
    }) {
      final observer = ImpressionsObserver();
      final counter = ImpressionsCounter();
      final store = InMemoryImpressionsStore();
      final ImpressionStrategy strategy;
      switch (mode) {
        case ImpressionsMode.debug:
          strategy = DebugImpressionStrategy(
            observer: observer,
            store: store,
          );
        case ImpressionsMode.optimized:
          strategy = OptimizedImpressionStrategy(
            observer: observer,
            counter: counter,
            store: store,
          );
        case ImpressionsMode.none:
          strategy = NoneImpressionStrategy(
            counter: counter,
            tracker: UniqueKeysTracker(),
          );
      }
      final manager = ImpressionsManager(
        strategy: strategy,
        listener: listener,
        consentProvider: consentProvider,
        log: SplitLogger(level: LogLevel.none),
      );
      return (manager: manager, store: store);
    }

    group('DEBUG mode', () {
      test('all impressions are queued', () {
        final (:manager, :store) = makeManager(mode: ImpressionsMode.debug);

        manager.record(makeImpression(), false, null);
        manager.record(makeImpression(), false, null);

        expect(store.popAll(), hasLength(2));
      });

      test('sets pt field from observer', () {
        final (:manager, :store) = makeManager(mode: ImpressionsMode.debug);

        manager.record(makeImpression(time: 1000), false, null);
        manager.record(makeImpression(time: 2000), false, null);

        final impressions = store.popAll();
        expect(impressions[0].pt, isNull);
        expect(impressions[1].pt, equals(1000));
      });

      test('duplicate impressions are still queued in debug mode', () {
        final (:manager, :store) = makeManager(mode: ImpressionsMode.debug);

        manager.record(makeImpression(time: 1000), false, null);
        manager.record(makeImpression(time: 2000), false, null);
        manager.record(makeImpression(time: 3000), false, null);

        expect(store.popAll(), hasLength(3));
      });
    });

    group('OPTIMIZED mode', () {
      test('deduplicates - same impression only queued once', () {
        final (:manager, :store) = makeManager(mode: ImpressionsMode.optimized);

        manager.record(makeImpression(time: 1000), false, null);
        manager.record(makeImpression(time: 2000), false, null);

        expect(store.popAll(), hasLength(1));
      });

      test('different impressions are all queued', () {
        final (:manager, :store) = makeManager(mode: ImpressionsMode.optimized);

        manager.record(
            makeImpression(feature: 'feat_a', time: 1000), false, null);
        manager.record(
            makeImpression(feature: 'feat_b', time: 2000), false, null);

        expect(store.popAll(), hasLength(2));
      });

      test('counts are always recorded regardless of dedup', () {
        final counter = ImpressionsCounter();
        final observer = ImpressionsObserver();
        final store = InMemoryImpressionsStore();
        final strategy = OptimizedImpressionStrategy(
          observer: observer,
          counter: counter,
          store: store,
        );
        final manager = ImpressionsManager(
          strategy: strategy,
          consentProvider: _grantedConsent,
          log: SplitLogger(level: LogLevel.none),
        );

        manager.record(makeImpression(time: 3600000), false, null);
        manager.record(makeImpression(time: 3600001), false, null);

        final counts = counter.popAll();
        expect(counts['feat::3600000'], equals(2));
      });

      test('counts are recorded even when impression is deduplicated', () {
        final counter = ImpressionsCounter();
        final observer = ImpressionsObserver();
        final store = InMemoryImpressionsStore();
        final strategy = OptimizedImpressionStrategy(
          observer: observer,
          counter: counter,
          store: store,
        );
        final manager = ImpressionsManager(
          strategy: strategy,
          consentProvider: _grantedConsent,
          log: SplitLogger(level: LogLevel.none),
        );

        manager.record(makeImpression(time: 3600000), false, null);
        manager.record(makeImpression(time: 3600500), false, null);
        manager.record(makeImpression(time: 3600900), false, null);

        expect(store.popAll(), hasLength(1));

        final counts = counter.popAll();
        expect(counts['feat::3600000'], equals(3));
      });
    });

    group('NONE mode', () {
      test('no impressions are recorded', () {
        final (:manager, :store) = makeManager(mode: ImpressionsMode.none);

        manager.record(makeImpression(), false, null);

        expect(store.popAll(), isEmpty);
      });
    });

    group('consent', () {
      test('DECLINED drops impressions', () {
        final (:manager, :store) = makeManager(
          mode: ImpressionsMode.debug,
          consentProvider: () => ConsentStatus.declined,
        );

        manager.record(makeImpression(), false, null);

        expect(store.popAll(), isEmpty);
      });

      test('GRANTED records normally', () {
        final (:manager, :store) = makeManager(mode: ImpressionsMode.debug);

        manager.record(makeImpression(), false, null);

        expect(store.popAll(), hasLength(1));
      });

      test('UNKNOWN records normally', () {
        final (:manager, :store) = makeManager(
          mode: ImpressionsMode.debug,
          consentProvider: () => ConsentStatus.unknown,
        );

        manager.record(makeImpression(), false, null);

        expect(store.popAll(), hasLength(1));
      });
    });

    group('ImpressionListener', () {
      test('fires for every impression', () async {
        final listener = _FakeListener();
        final (:manager, store: _) = makeManager(
          mode: ImpressionsMode.debug,
          listener: listener,
        );

        manager.record(makeImpression(feature: 'a'), false, null);
        manager.record(makeImpression(feature: 'b'), false, null);

        await Future<void>.value();
        expect(listener.logged, hasLength(2));
        expect(listener.logged[0].feature, equals('a'));
        expect(listener.logged[1].feature, equals('b'));
      });

      test('fires even when consent is declined', () async {
        final listener = _FakeListener();
        final (:manager, :store) = makeManager(
          mode: ImpressionsMode.debug,
          listener: listener,
          consentProvider: () => ConsentStatus.declined,
        );

        manager.record(makeImpression(), false, null);

        await Future<void>.value();
        expect(listener.logged, hasLength(1));
        expect(store.popAll(), isEmpty);
      });

      test('passes attributes to listener', () async {
        final listener = _FakeListener();
        final (:manager, store: _) = makeManager(
          mode: ImpressionsMode.debug,
          listener: listener,
        );

        final attrs = <String, Object?>{'plan': 'premium'};
        manager.record(makeImpression(), false, attrs);

        await Future<void>.value();
        expect(listener.logged[0].attributes, equals(attrs));
      });

      test('exceptions in listener are caught and do not propagate', () async {
        final listener = _FakeListener()..shouldThrow = true;
        final (:manager, :store) = makeManager(
          mode: ImpressionsMode.debug,
          listener: listener,
        );

        manager.record(makeImpression(), false, null);

        expect(store.popAll(), hasLength(1));
        await Future<void>.value();
      });
    });
  });
}

ConsentStatus _grantedConsent() => ConsentStatus.granted;
