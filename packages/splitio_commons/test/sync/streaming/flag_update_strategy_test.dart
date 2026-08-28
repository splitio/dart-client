import 'dart:convert';

import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/streaming/flag_update_strategy.dart';
import 'package:splitio_commons/src/sync/streaming/notification_processor.dart';
import 'package:test/test.dart';

/// Encodes a split definition map to the base64(utf8(JSON)) form used in a
/// `SPLIT_UPDATE` `d` field (uncompressed, c == 0).
String _encode(Map<String, dynamic> def) =>
    base64.encode(utf8.encode(jsonEncode(def)));

Map<String, dynamic> _def({
  required String name,
  int changeNumber = 200,
  String status = 'ACTIVE',
  bool killed = false,
  String defaultTreatment = 'off',
}) =>
    {
      'name': name,
      'trafficTypeName': 'user',
      'killed': killed,
      'defaultTreatment': defaultTreatment,
      'conditions': [],
      'trafficAllocation': 100,
      'seed': 12345,
      'algo': 2,
      'changeNumber': changeNumber,
      'status': status,
    };

FeedUpdate _splitUpdate({
  required int changeNumber,
  required int pcn,
  required int c,
  required String d,
}) =>
    FeedUpdate(type: 'SPLIT_UPDATE', payload: {
      'type': 'SPLIT_UPDATE',
      'changeNumber': changeNumber,
      'pcn': pcn,
      'c': c,
      'd': d,
    });

FeedUpdate _splitKill({
  required int changeNumber,
  required String splitName,
  required String defaultTreatment,
}) =>
    FeedUpdate(type: 'SPLIT_KILL', payload: {
      'type': 'SPLIT_KILL',
      'changeNumber': changeNumber,
      'splitName': splitName,
      'defaultTreatment': defaultTreatment,
    });

InMemoryRuleStore _seededStore({int changeNumber = 100, String? existing}) {
  final store = InMemoryRuleStore();
  store.applyChange(Change(
    changeNumber: changeNumber,
    updates: {
      if (existing != null)
        existing: ParsedSplit(
          name: existing,
          trafficTypeName: 'user',
          killed: false,
          defaultTreatment: 'off',
          conditions: const [],
          trafficAllocation: 100,
          seed: 1,
          algo: 2,
          changeNumber: changeNumber,
        ),
    },
  ));
  return store;
}

void main() {
  group('SPLIT_UPDATE', () {
    test('c==0 && pcn==stored → applied in place, no fetch', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: _encode(_def(name: 'flag_a', changeNumber: 200)),
      ));

      expect(result.outcome, FlagUpdateOutcome.appliedInPlace);
      expect(result.didApplyInPlace, isTrue);
      expect(store.changeNumber(), 200);
      expect(store.get('flag_a'), isNotNull);
      expect(store.get('flag_a')!.changeNumber, 200);
    });

    test('c==0 but pcn != stored → fetch fallback, store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 50,
        c: 0,
        d: _encode(_def(name: 'flag_a')),
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.changeNumber(), 100);
      expect(store.get('flag_a'), isNull);
    });

    test('c==1 (gzip) → fetch fallback (deferred), store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 1,
        d: _encode(_def(name: 'flag_a')),
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(store.changeNumber(), 100);
    });

    test('c==2 (zlib) → fetch fallback (deferred), store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 2,
        d: _encode(_def(name: 'flag_a')),
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(store.changeNumber(), 100);
    });

    test('unknown c → fetch fallback', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 9,
        d: _encode(_def(name: 'flag_a')),
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(store.changeNumber(), 100);
    });

    test('archived/inactive split → removed in place when c==0 && pcn matches',
        () {
      final store = _seededStore(changeNumber: 100, existing: 'flag_a');
      final strategy = FlagUpdateStrategy(ruleStore: store);
      expect(store.get('flag_a'), isNotNull);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: _encode(_def(name: 'flag_a', status: 'ARCHIVED')),
      ));

      expect(result.outcome, FlagUpdateOutcome.appliedInPlace);
      expect(result.didApplyInPlace, isTrue);
      expect(store.get('flag_a'), isNull);
      expect(store.changeNumber(), 200);
    });

    test('malformed base64 → fetch fallback, no throw, store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: '!!!not-base64!!!',
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(store.changeNumber(), 100);
    });

    test('valid base64 but bad JSON → fetch fallback, store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: base64.encode(utf8.encode('not json')),
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(store.changeNumber(), 100);
    });

    test('JSON is not an object → fetch fallback', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: base64.encode(utf8.encode('[1,2,3]')),
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(store.changeNumber(), 100);
    });

    test('missing fields (non-int changeNumber) → fetch fallback', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(FeedUpdate(type: 'SPLIT_UPDATE', payload: {
        'type': 'SPLIT_UPDATE',
        'pcn': 100,
        'c': 0,
        'd': _encode(_def(name: 'flag_a')),
      }));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(store.changeNumber(), 100);
    });

    test('c present but not an int (string "0") → fetch fallback, untouched',
        () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(FeedUpdate(type: 'SPLIT_UPDATE', payload: {
        'type': 'SPLIT_UPDATE',
        'changeNumber': 200,
        'pcn': 100,
        'c': '0',
        'd': _encode(_def(name: 'flag_a')),
      }));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.changeNumber(), 100);
      expect(store.get('flag_a'), isNull);
    });

    test('c is null → fetch fallback, store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(FeedUpdate(type: 'SPLIT_UPDATE', payload: {
        'type': 'SPLIT_UPDATE',
        'changeNumber': 200,
        'pcn': 100,
        'c': null,
        'd': _encode(_def(name: 'flag_a')),
      }));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.changeNumber(), 100);
    });

    test('pcn present but not an int → fetch fallback, store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(FeedUpdate(type: 'SPLIT_UPDATE', payload: {
        'type': 'SPLIT_UPDATE',
        'changeNumber': 200,
        'pcn': '100',
        'c': 0,
        'd': _encode(_def(name: 'flag_a')),
      }));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.changeNumber(), 100);
      expect(store.get('flag_a'), isNull);
    });

    test('empty d string (c==0, pcn matches) → fetch fallback, no throw', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: '',
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.changeNumber(), 100);
    });

    test('d decodes to a JSON list → fetch fallback, no throw', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: base64.encode(utf8.encode(jsonEncode([
          {'name': 'flag_a'}
        ]))),
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.changeNumber(), 100);
    });

    test('missing pcn, c and d entirely → fetch fallback, no throw', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(const FeedUpdate(
        type: 'SPLIT_UPDATE',
        payload: {
          'type': 'SPLIT_UPDATE',
          'changeNumber': 200,
        },
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.changeNumber(), 100);
    });
  });

  group('SPLIT_KILL', () {
    test('present flag → killed in place AND fetch required', () {
      final store = _seededStore(changeNumber: 100, existing: 'flag_a');
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitKill(
        changeNumber: 200,
        splitName: 'flag_a',
        defaultTreatment: 'on',
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isTrue);
      final killed = store.get('flag_a')!;
      expect(killed.killed, isTrue);
      expect(killed.defaultTreatment, 'on');
      expect(killed.changeNumber, 200);
      expect(store.changeNumber(), 200);
    });

    test('absent flag → fetch required, no crash, store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitKill(
        changeNumber: 200,
        splitName: 'missing',
        defaultTreatment: 'on',
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.get('missing'), isNull);
      expect(store.changeNumber(), 100);
    });

    test('stale changeNumber → fetch required, no in-place apply', () {
      final store = _seededStore(changeNumber: 100, existing: 'flag_a');
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitKill(
        changeNumber: 50,
        splitName: 'flag_a',
        defaultTreatment: 'on',
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.get('flag_a')!.killed, isFalse);
      expect(store.changeNumber(), 100);
    });

    test('missing defaultTreatment → fetch required, no crash, untouched', () {
      final store = _seededStore(changeNumber: 100, existing: 'flag_a');
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(const FeedUpdate(
        type: 'SPLIT_KILL',
        payload: {
          'type': 'SPLIT_KILL',
          'changeNumber': 200,
          'splitName': 'flag_a',
        },
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.get('flag_a')!.killed, isFalse);
      expect(store.changeNumber(), 100);
    });

    test('non-string splitName → fetch required, no crash, untouched', () {
      final store = _seededStore(changeNumber: 100, existing: 'flag_a');
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(const FeedUpdate(
        type: 'SPLIT_KILL',
        payload: {
          'type': 'SPLIT_KILL',
          'changeNumber': 200,
          'splitName': 42,
          'defaultTreatment': 'on',
        },
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.get('flag_a')!.killed, isFalse);
      expect(store.changeNumber(), 100);
    });

    test('non-int changeNumber → fetch required, no crash, untouched', () {
      final store = _seededStore(changeNumber: 100, existing: 'flag_a');
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(const FeedUpdate(
        type: 'SPLIT_KILL',
        payload: {
          'type': 'SPLIT_KILL',
          'changeNumber': '200',
          'splitName': 'flag_a',
          'defaultTreatment': 'on',
        },
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(store.get('flag_a')!.killed, isFalse);
      expect(store.changeNumber(), 100);
    });
  });

  group('unknown type', () {
    test('non-flag update → fetch fallback', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy
          .handle(const FeedUpdate(type: 'MEMBERSHIPS_MS_UPDATE', payload: {}));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
    });
  });
}
