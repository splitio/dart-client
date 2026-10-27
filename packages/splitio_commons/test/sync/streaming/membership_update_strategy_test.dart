import 'dart:async';
import 'dart:convert';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/streaming/membership_payload_decoder.dart';
import 'package:splitio_commons/src/sync/streaming/membership_update_strategy.dart';
import 'package:splitio_commons/src/sync/streaming/notification_processor.dart';
import 'package:test/test.dart';

import '../compression/inflate_vectors.dart';

void main() {
  const decoder = MembershipPayloadDecoder();
  const matchingKey = 'user_1';

  late InMemoryMembershipStore store;
  late MembershipUpdateStrategy strategy;

  setUp(() {
    store = InMemoryMembershipStore();
    strategy = MembershipUpdateStrategy(store: store, decoder: decoder);
  });

  // Base64 of a plain JSON string (c == 0, NONE).
  String b64(String s) => base64.encode(utf8.encode(s));

  FeedUpdate msUpdate(Map<String, dynamic> extra) => FeedUpdate(
        type: 'MEMBERSHIPS_MS_UPDATE',
        payload: {'type': 'MEMBERSHIPS_MS_UPDATE', ...extra},
      );

  FeedUpdate lsUpdate(Map<String, dynamic> extra) => FeedUpdate(
        type: 'MEMBERSHIPS_LS_UPDATE',
        payload: {'type': 'MEMBERSHIPS_LS_UPDATE', ...extra},
      );

  // Decimal-string hash of the matching key (key-list comparison value).
  final keyHash = decoder.hashKeyDecimal(matchingKey);

  group('UNBOUNDED_FETCH_REQUEST (0)', () {
    test('requires unbounded fetch, no store change', () {
      final r = strategy.handle(msUpdate({'u': 0, 'cn': 5}), matchingKey);
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
      expect(store.hasKey(matchingKey), isFalse);
    });
  });

  group('BOUNDED_FETCH_REQUEST (1)', () {
    // javascript-commons dataMocks.ts bitmaps[0] (gzip): the first key has its
    // bit set, the second does not.
    const inBitmap = '88f8b33b-f858-4aea-bea2-a5f066bab3ce';
    const notInBitmap = '88f8b33b-f858-4aea-bea2-a5f066bab3c0';

    test('gzip bitmap, key bit set → unbounded fetch, no store change', () {
      final r = strategy.handle(
        msUpdate({'u': 1, 'cn': 5, 'c': 1, 'd': jsBitmap0Gzip}),
        inBitmap,
      );
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
      expect(store.hasKey(inBitmap), isFalse);
    });

    test('gzip bitmap, key bit not set → no fetch, no store change', () {
      final r = strategy.handle(
        msUpdate({'u': 1, 'cn': 5, 'c': 1, 'd': jsBitmap0Gzip}),
        notInBitmap,
      );
      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isFalse);
      expect(store.hasKey(notInBitmap), isFalse);
    });

    test('zlib bitmap: fetches exactly for the keys whose bit is set', () {
      final plain = base64.decode(jsBitmap1Plain);
      final update = msUpdate({'u': 1, 'cn': 5, 'c': 2, 'd': jsBitmap1Zlib});
      var hits = 0;
      for (var i = 0; i < 400; i++) {
        final k = 'key_$i';
        final expected = decoder.isInBitmap(decoder.hashKeyLow32(k), plain);
        if (expected) hits++;
        expect(strategy.handle(update, k).fetchRequired, expected, reason: k);
      }
      // Keep the test meaningful: bitmap is sparse, so also probe until a
      // hit is found to prove the positive path.
      for (var i = 400; hits == 0 && i < 400000; i++) {
        final k = 'key_$i';
        if (decoder.isInBitmap(decoder.hashKeyLow32(k), plain)) {
          expect(strategy.handle(update, k).fetchRequired, isTrue);
          hits++;
        }
      }
      expect(hits, greaterThan(0));
    });

    test('c == 0 bitmap is base64-only', () {
      final bitmap = List<int>.filled(8, 0);
      final bit = decoder.hashKeyLow32(matchingKey) % 64;
      bitmap[bit ~/ 8] |= 1 << (bit % 8);
      final r = strategy.handle(
        msUpdate({'u': 1, 'cn': 5, 'c': 0, 'd': base64.encode(bitmap)}),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
    });

    test('unpadded base64 d is accepted', () {
      final r = strategy.handle(
        msUpdate(
            {'u': 1, 'cn': 5, 'c': 1, 'd': jsBitmap0Gzip.replaceAll('=', '')}),
        notInBitmap,
      );
      expect(r.fetchRequired, isFalse);
    });

    test('absent d → unbounded fetch, no WARNING', () async {
      final logs = <String>[];
      final logged = MembershipUpdateStrategy(
        store: store,
        decoder: decoder,
        logger: SplitLogger(level: LogLevel.verbose),
      );
      runZoned(() {
        expect(
            logged
                .handle(msUpdate({'u': 1, 'cn': 5, 'c': 1}), matchingKey)
                .fetchRequired,
            isTrue);
        expect(
            logged
                .handle(
                    msUpdate({'u': 1, 'cn': 5, 'c': 1, 'd': ''}), matchingKey)
                .fetchRequired,
            isTrue);
      },
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => logs.add(line),
          ));
      expect(logs, isEmpty);
    });

    test('decode error → unbounded fetch for every key, ONE WARNING', () {
      final logs = <String>[];
      final logged = MembershipUpdateStrategy(
        store: store,
        decoder: decoder,
        logger: SplitLogger(level: LogLevel.warning),
      );
      final update = msUpdate({'u': 1, 'cn': 5, 'c': 1, 'd': malformedBounded});
      runZoned(() {
        for (final k in ['k1', 'k2', 'k3']) {
          final r = logged.handle(update, k);
          expect(r.fetchRequired, isTrue, reason: k);
          expect(r.didApplyInPlace, isFalse);
        }
      },
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => logs.add(line),
          ));

      expect(logs, hasLength(1));
      expect(
          logs.single,
          allOf(
            contains('[WARNING]'),
            contains('Fetching Memberships due to an error processing '
                'BoundedFetchRequest notification: '),
          ));

      // A different notification with a decode error logs again.
      runZoned(() {
        logged.handle(
            msUpdate({'u': 1, 'cn': 6, 'c': 1, 'd': malformedBounded}), 'k1');
      },
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => logs.add(line),
          ));
      expect(logs, hasLength(2));
    });

    test('unknown c → unbounded fetch', () {
      final r = strategy.handle(
        msUpdate({'u': 1, 'cn': 5, 'c': 3, 'd': jsBitmap0Gzip}),
        notInBitmap,
      );
      expect(r.fetchRequired, isTrue);
    });
  });

  group('KEY_LIST (2)', () {
    setUp(() {
      store.applyMembership(
        matchingKey,
        const MembershipChange(
          changeNumber: 1,
          mySegments: {'existing_ms'},
          largeSegments: {'existing_ls'},
        ),
      );
    });

    test('ADD adds named MS segments in place, preserving LS + existing MS',
        () {
      final d = b64('{"a":[$keyHash],"r":[]}');
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 0,
          'd': d,
          'n': ['new_seg']
        }),
        matchingKey,
      );

      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isTrue);
      // whenUpdated() wiring (spec §4.6/§8.2, BUG #12): an in-place apply
      // that actually adds a key MUST be reported as a change.
      expect(r.changed, isTrue);
      expect(store.mySegmentsForKey(matchingKey),
          equals({'existing_ms', 'new_seg'}));
      expect(store.largeSegmentsForKey(matchingKey), equals({'existing_ls'}));
      expect(store.changeNumber(matchingKey), equals(9));
    });

    test('REMOVE removes named segments in place, preserving others', () {
      final d = b64('{"a":[],"r":[$keyHash]}');
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 0,
          'd': d,
          'n': ['existing_ms']
        }),
        matchingKey,
      );

      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isTrue);
      expect(r.changed, isTrue);
      expect(store.mySegmentsForKey(matchingKey), isEmpty);
      expect(store.largeSegmentsForKey(matchingKey), equals({'existing_ls'}));
    });

    test('NONE (hash in neither a nor r) → no change, no fetch', () {
      final d = b64('{"a":[123],"r":[456]}');
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 0,
          'd': d,
          'n': ['new_seg']
        }),
        matchingKey,
      );

      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isFalse);
      // No membership actually changed — whenUpdated() MUST NOT fire.
      expect(r.changed, isFalse);
      expect(store.mySegmentsForKey(matchingKey), equals({'existing_ms'}));
      expect(store.largeSegmentsForKey(matchingKey), equals({'existing_ls'}));
      expect(store.changeNumber(matchingKey), equals(1));
    });

    test('LS update affects largeSegments, not mySegments', () {
      final d = b64('{"a":[$keyHash],"r":[]}');
      final r = strategy.handle(
        lsUpdate({
          'u': 2,
          'cn': 9,
          'c': 0,
          'd': d,
          'n': ['new_ls']
        }),
        matchingKey,
      );

      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isTrue);
      expect(r.changed, isTrue);
      expect(store.largeSegmentsForKey(matchingKey),
          equals({'existing_ls', 'new_ls'}));
      expect(store.mySegmentsForKey(matchingKey), equals({'existing_ms'}));
    });

    test('c == 1 (gzip) KEY_LIST with the key in `a` → applied in place', () {
      // javascript-commons dataMocks.ts keylists[0]: `key1` is in `a`.
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 1,
          'd': jsKeyListGzip,
          'n': ['new_seg']
        }),
        'key1',
      );
      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isTrue);
      expect(r.changed, isTrue);
      expect(store.mySegmentsForKey('key1'), equals({'new_seg'}));
    });

    test('c == 1 (gzip) KEY_LIST with the key in neither list → no-op', () {
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 1,
          'd': jsKeyListGzip,
          'n': ['new_seg']
        }),
        'someone_else',
      );
      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isFalse);
    });

    test('c == 1 with non-gzip data → unbounded fetch fallback', () {
      final d = b64('{"a":[$keyHash],"r":[]}');
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 1,
          'd': d,
          'n': ['new_seg']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
      expect(store.mySegmentsForKey(matchingKey), equals({'existing_ms'}));
    });

    test('c == 2 with non-zlib data → unbounded fetch fallback', () {
      final d = b64('{"a":[$keyHash],"r":[]}');
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 2,
          'd': d,
          'n': ['new_seg']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
    });

    test('unknown c → unbounded fetch fallback', () {
      final d = b64('{"a":[$keyHash],"r":[]}');
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 3,
          'd': d,
          'n': ['x']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
    });

    test('decode error → fetch for every key, ONE WARNING', () {
      final logs = <String>[];
      final logged = MembershipUpdateStrategy(
        store: store,
        decoder: decoder,
        logger: SplitLogger(level: LogLevel.warning),
      );
      final update = msUpdate({
        'u': 2,
        'cn': 9,
        'c': 1,
        'd': malformedBounded,
        'n': ['x']
      });
      runZoned(() {
        for (final k in ['k1', 'k2', 'k3']) {
          expect(logged.handle(update, k).fetchRequired, isTrue, reason: k);
        }
      },
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => logs.add(line),
          ));
      expect(logs, hasLength(1));
      expect(
          logs.single,
          contains('Fetching Memberships due to an error processing KeyList '
              'notification: '));
    });

    test('malformed base64 d → unbounded fetch fallback, no throw', () {
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 0,
          'd': '!!!not base64!!!',
          'n': ['x']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
    });

    test('bad JSON payload → unbounded fetch fallback', () {
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 0,
          'd': b64('not json'),
          'n': ['x']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
    });

    test('missing d → unbounded fetch fallback', () {
      final r = strategy.handle(
        msUpdate({
          'u': 2,
          'cn': 9,
          'c': 0,
          'n': ['x']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
    });

    test('ADD with missing names → no-op names but still applies (empty)', () {
      final d = b64('{"a":[$keyHash],"r":[]}');
      final r = strategy.handle(
        msUpdate({'u': 2, 'cn': 9, 'c': 0, 'd': d}),
        matchingKey,
      );
      // ADD with no names to add: nothing added, still counts as in-place
      // (cn advanced) with no fetch.
      expect(r.fetchRequired, isFalse);
      // Nothing was actually added to the membership set — not a change.
      expect(r.changed, isFalse);
      expect(store.mySegmentsForKey(matchingKey), equals({'existing_ms'}));
    });
  });

  group('SEGMENT_REMOVAL (3)', () {
    setUp(() {
      store.applyMembership(
        matchingKey,
        const MembershipChange(
          changeNumber: 1,
          mySegments: {'seg_a', 'seg_b'},
          largeSegments: {'ls_a'},
        ),
      );
    });

    test('removes named MS segments in place', () {
      final r = strategy.handle(
        msUpdate({
          'u': 3,
          'cn': 9,
          'n': ['seg_a']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isTrue);
      expect(r.changed, isTrue);
      expect(store.mySegmentsForKey(matchingKey), equals({'seg_b'}));
      expect(store.largeSegmentsForKey(matchingKey), equals({'ls_a'}));
      expect(store.changeNumber(matchingKey), equals(9));
    });

    test('LS segment removal affects largeSegments only', () {
      final r = strategy.handle(
        lsUpdate({
          'u': 3,
          'cn': 9,
          'n': ['ls_a']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isFalse);
      expect(r.changed, isTrue);
      expect(store.largeSegmentsForKey(matchingKey), isEmpty);
      expect(store.mySegmentsForKey(matchingKey), equals({'seg_a', 'seg_b'}));
    });

    test('missing names → unbounded fetch fallback', () {
      final r = strategy.handle(
        msUpdate({'u': 3, 'cn': 9}),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
    });

    test(
        'removing a segment the key never had is applied in place but is '
        'NOT a change (whenUpdated() MUST NOT fire)', () {
      final r = strategy.handle(
        msUpdate({
          'u': 3,
          'cn': 9,
          'n': ['never_had_this_one']
        }),
        matchingKey,
      );
      expect(r.fetchRequired, isFalse);
      expect(r.didApplyInPlace, isTrue);
      expect(r.changed, isFalse);
      expect(store.mySegmentsForKey(matchingKey), equals({'seg_a', 'seg_b'}));
    });
  });

  group('error / unknown', () {
    test('unknown strategy code → unbounded fetch fallback', () {
      final r = strategy.handle(msUpdate({'u': 99, 'cn': 5}), matchingKey);
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
    });

    test('missing u → unbounded fetch fallback', () {
      final r = strategy.handle(msUpdate({'cn': 5}), matchingKey);
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
    });

    test('non-int u → unbounded fetch fallback', () {
      final r = strategy.handle(msUpdate({'u': 'zero'}), matchingKey);
      expect(r.fetchRequired, isTrue);
    });
  });
}
