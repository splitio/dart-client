import 'dart:async';
import 'dart:convert';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/streaming/flag_update_strategy.dart';
import 'package:splitio_commons/src/sync/streaming/notification_processor.dart';
import 'package:test/test.dart';

import '../compression/inflate_vectors.dart';

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

    test('c==1 (gzip) && pcn==stored → applied in place, no fetch', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: jsSplit0ChangeNumber,
        pcn: 100,
        c: 1,
        d: jsSplit0C1,
      ));

      expect(result.outcome, FlagUpdateOutcome.appliedInPlace);
      expect(result.didApplyInPlace, isTrue);
      expect(store.changeNumber(), jsSplit0ChangeNumber);
      expect(store.get(jsSplit0Name), isNotNull);
    });

    test('c==2 (zlib) && pcn==stored → applied in place, no fetch', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: jsSplit1ChangeNumber,
        pcn: 100,
        c: 2,
        d: jsSplit1C2,
      ));

      expect(result.outcome, FlagUpdateOutcome.appliedInPlace);
      expect(store.changeNumber(), jsSplit1ChangeNumber);
      expect(store.get(jsSplit1Name), isNotNull);
    });

    test('c==1 (gzip) but pcn != stored → fetch fallback, store untouched', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: jsSplit0ChangeNumber,
        pcn: 50,
        c: 1,
        d: jsSplit0C1,
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(store.changeNumber(), 100);
    });

    group('decode errors', () {
      Future<List<String>> capture(void Function() body) async {
        final lines = <String>[];
        runZoned(
          body,
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => lines.add(line),
          ),
        );
        return lines;
      }

      test('corrupt gzip → fetch fallback + one WARNING with the error',
          () async {
        final store = _seededStore(changeNumber: 100);
        final strategy = FlagUpdateStrategy(
          ruleStore: store,
          logger: SplitLogger(level: LogLevel.warning),
        );
        late FlagUpdateResult result;

        final logs = await capture(() {
          result = strategy.handle(_splitUpdate(
            changeNumber: 200,
            pcn: 100,
            c: 1,
            d: malformedBounded,
          ));
        });

        expect(result.outcome, FlagUpdateOutcome.fetchRequired);
        expect(store.changeNumber(), 100);
        expect(logs, hasLength(1));
        expect(
            logs.single,
            allOf(
              contains('[WARNING]'),
              contains('Fetching SplitChanges due to an error processing '
                  'SPLIT_UPDATE notification: '),
            ));
      });

      test('empty d → fetch fallback, no WARNING', () async {
        final store = _seededStore(changeNumber: 100);
        final strategy = FlagUpdateStrategy(
          ruleStore: store,
          logger: SplitLogger(level: LogLevel.verbose),
        );
        late FlagUpdateResult result;

        final logs = await capture(() {
          result = strategy
              .handle(_splitUpdate(changeNumber: 200, pcn: 100, c: 2, d: ''));
        });

        expect(result.outcome, FlagUpdateOutcome.fetchRequired);
        expect(logs, isEmpty);
      });

      test('unknown c → fetch fallback, no WARNING', () async {
        final store = _seededStore(changeNumber: 100);
        final strategy = FlagUpdateStrategy(
          ruleStore: store,
          logger: SplitLogger(level: LogLevel.verbose),
        );
        late FlagUpdateResult result;

        final logs = await capture(() {
          result = strategy.handle(
              _splitUpdate(changeNumber: 200, pcn: 100, c: 3, d: jsSplit0C1));
        });

        expect(result.outcome, FlagUpdateOutcome.fetchRequired);
        expect(logs, isEmpty);
      });
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

    test('DELETED split (archive via admin) → removed in place', () {
      final store = _seededStore(changeNumber: 100, existing: 'flag_a');
      final strategy = FlagUpdateStrategy(ruleStore: store);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: _encode(_def(name: 'flag_a', status: 'DELETED')),
      ));

      expect(result.outcome, FlagUpdateOutcome.appliedInPlace);
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

    test('applied in place → onApplied fires with the changed flag name', () {
      final store = _seededStore(changeNumber: 100);
      final applied = <List<String>>[];
      final strategy =
          FlagUpdateStrategy(ruleStore: store, onApplied: applied.add);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 100,
        c: 0,
        d: _encode(_def(name: 'flag_a', changeNumber: 200)),
      ));

      expect(result.outcome, FlagUpdateOutcome.appliedInPlace);
      expect(applied, [
        ['flag_a']
      ]);
    });

    test('fetch fallback (pcn mismatch) → onApplied does NOT fire', () {
      final store = _seededStore(changeNumber: 100);
      final applied = <List<String>>[];
      final strategy =
          FlagUpdateStrategy(ruleStore: store, onApplied: applied.add);

      final result = strategy.handle(_splitUpdate(
        changeNumber: 200,
        pcn: 50,
        c: 0,
        d: _encode(_def(name: 'flag_a')),
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(applied, isEmpty);
    });

    test('onApplied is optional — handle() does not throw when omitted', () {
      final store = _seededStore(changeNumber: 100);
      final strategy = FlagUpdateStrategy(ruleStore: store);

      expect(
        () => strategy.handle(_splitUpdate(
          changeNumber: 200,
          pcn: 100,
          c: 0,
          d: _encode(_def(name: 'flag_a', changeNumber: 200)),
        )),
        returnsNormally,
      );
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
      // The store-wide `ff` cursor MUST NOT advance from an in-place kill
      // (spec §10.2) — only the killed split's own changeNumber (asserted
      // above) reflects the kill. The follow-up fetch this outcome always
      // requires is what actually converges the cursor to 200.
      expect(store.changeNumber(), 100);
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

    test(
        'present flag → onApplied fires with the killed flag name, even '
        'though a fetch is also required', () {
      final store = _seededStore(changeNumber: 100, existing: 'flag_a');
      final applied = <List<String>>[];
      final strategy =
          FlagUpdateStrategy(ruleStore: store, onApplied: applied.add);

      final result = strategy.handle(_splitKill(
        changeNumber: 200,
        splitName: 'flag_a',
        defaultTreatment: 'on',
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isTrue);
      expect(applied, [
        ['flag_a']
      ]);
    });

    test('absent flag → kill not applied, onApplied does NOT fire', () {
      final store = _seededStore(changeNumber: 100);
      final applied = <List<String>>[];
      final strategy =
          FlagUpdateStrategy(ruleStore: store, onApplied: applied.add);

      final result = strategy.handle(_splitKill(
        changeNumber: 200,
        splitName: 'missing',
        defaultTreatment: 'on',
      ));

      expect(result.outcome, FlagUpdateOutcome.fetchRequired);
      expect(result.didApplyInPlace, isFalse);
      expect(applied, isEmpty);
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
