import 'dart:convert';

import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/streaming/membership_payload_decoder.dart';
import 'package:splitio_commons/src/sync/streaming/membership_update_strategy.dart';
import 'package:splitio_commons/src/sync/streaming/notification_processor.dart';
import 'package:test/test.dart';

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
    test('falls back to unbounded fetch (decompression deferred)', () {
      final r = strategy.handle(
        msUpdate({'u': 1, 'cn': 5, 'c': 0, 'd': b64('anything')}),
        matchingKey,
      );
      expect(r.fetchRequired, isTrue);
      expect(r.didApplyInPlace, isFalse);
      expect(store.hasKey(matchingKey), isFalse);
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
      expect(store.largeSegmentsForKey(matchingKey),
          equals({'existing_ls', 'new_ls'}));
      expect(store.mySegmentsForKey(matchingKey), equals({'existing_ms'}));
    });

    test('c == 1 (gzip) → unbounded fetch fallback', () {
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

    test('c == 2 (zlib) → unbounded fetch fallback', () {
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
