import 'dart:convert';

import 'package:splitio_commons/src/storage/storage.dart';

import 'membership_payload_decoder.dart';
import 'notification_processor.dart';

/// The result of a single [MembershipUpdateStrategy.handle] call (spec §12.2).
///
/// [fetchRequired] means the caller (StreamingManager, task 4.7) MUST trigger an
/// **unbounded** full memberships fetch for the user key — either because the
/// strategy mandates it, decompression is deferred, or in-place apply was not
/// safe. [didApplyInPlace] records whether the store was mutated directly.
class MembershipUpdateResult {
  final bool fetchRequired;
  final bool didApplyInPlace;

  const MembershipUpdateResult({
    required this.fetchRequired,
    required this.didApplyInPlace,
  });

  static const MembershipUpdateResult _fetch = MembershipUpdateResult(
    fetchRequired: true,
    didApplyInPlace: false,
  );

  static const MembershipUpdateResult _noop = MembershipUpdateResult(
    fetchRequired: false,
    didApplyInPlace: false,
  );

  static const MembershipUpdateResult _applied = MembershipUpdateResult(
    fetchRequired: false,
    didApplyInPlace: true,
  );
}

/// Membership-side instant-update strategies for `MEMBERSHIPS_MS_UPDATE` and
/// `MEMBERSHIPS_LS_UPDATE` (spec §12.2). Pure of network I/O: it either mutates
/// the [MembershipStore] in place or signals the caller that an unbounded fetch
/// fallback is required. Never throws — any decode/processing error degrades to
/// an unbounded fetch (the safe default per §12.2).
///
/// Wire fields on the inner notification payload (spec §12.2/§12.3):
/// - `u` = updateStrategy code (0..3),
/// - `cn` = changeNumber,
/// - `c` = compression byte (0 NONE / 1 GZIP / 2 ZLIB),
/// - `d` = base64 payload (bitmap for BOUNDED, key-list JSON for KEY_LIST),
/// - `n` = segment names to add/remove (KEY_LIST / SEGMENT_REMOVAL).
///
/// `MEMBERSHIPS_MS_UPDATE` edits the key's **mySegments**; `MEMBERSHIPS_LS_UPDATE`
/// edits its **largeSegments**. The other locus is preserved on every in-place
/// apply (the store tracks the two sets separately).
///
/// Decompression is DEFERRED (mirrors the flag-side deferral): only `c == 0`
/// (base64-only) payloads are handled in place. BOUNDED always falls back to an
/// unbounded fetch (the bitmap needs gzip/zlib we can't yet inflate); KEY_LIST
/// with `c != 0` also falls back.
class MembershipUpdateStrategy {
  final MembershipStore _store;
  final MembershipPayloadDecoder _decoder;

  MembershipUpdateStrategy({
    required MembershipStore store,
    required MembershipPayloadDecoder decoder,
  })  : _store = store,
        _decoder = decoder;

  /// Handles a membership-side [update] for the bound [matchingKey], mutating
  /// the store in place when safe and returning whether an unbounded fetch is
  /// still required.
  MembershipUpdateResult handle(FeedUpdate update, String matchingKey) {
    try {
      final payload = update.payload;
      final u = payload['u'];
      if (u is! int) return MembershipUpdateResult._fetch;

      final isLarge = update.type == 'MEMBERSHIPS_LS_UPDATE';

      switch (u) {
        case 0: // UNBOUNDED_FETCH_REQUEST
          return MembershipUpdateResult._fetch;
        case 1: // BOUNDED_FETCH_REQUEST
          // TODO(streaming): once the Decompressor SPI lands, decode `d`,
          // compute isInBitmap(hashKeyLow32(key), keyMap) and fetch only when
          // the user's bit is set. Until then we always fall back to unbounded
          // fetch (the safe default per §12.2).
          return MembershipUpdateResult._fetch;
        case 2: // KEY_LIST
          return _handleKeyList(payload, matchingKey, isLarge);
        case 3: // SEGMENT_REMOVAL
          return _handleSegmentRemoval(payload, matchingKey, isLarge);
        default:
          return MembershipUpdateResult._fetch;
      }
    } catch (_) {
      return MembershipUpdateResult._fetch;
    }
  }

  MembershipUpdateResult _handleKeyList(
    Map<String, dynamic> payload,
    String matchingKey,
    bool isLarge,
  ) {
    final c = payload['c'];
    final d = payload['d'];
    // Decompression deferred: only base64-only (c == 0) payloads in place.
    if (c != 0 || d is! String) return MembershipUpdateResult._fetch;

    final jsonText = utf8.decode(base64.decode(d));
    final keyList = _decoder.parseKeyList(jsonText);
    final action = _decoder.resolveKeyListAction(
      _decoder.hashKeyDecimal(matchingKey),
      a: keyList.a,
      r: keyList.r,
    );

    if (action == KeyListAction.none) return MembershipUpdateResult._noop;

    final names = _names(payload);
    switch (action) {
      case KeyListAction.add:
        return _applyInPlace(payload, matchingKey, isLarge, add: names);
      case KeyListAction.remove:
        return _applyInPlace(payload, matchingKey, isLarge, remove: names);
      case KeyListAction.none:
        return MembershipUpdateResult._noop;
    }
  }

  MembershipUpdateResult _handleSegmentRemoval(
    Map<String, dynamic> payload,
    String matchingKey,
    bool isLarge,
  ) {
    final names = _names(payload);
    // SEGMENT_REMOVAL's entire payload is the names to remove; a missing/empty
    // list is malformed → fall back to the safe default.
    if (names.isEmpty) return MembershipUpdateResult._fetch;
    return _applyInPlace(payload, matchingKey, isLarge, remove: names);
  }

  /// Applies an in-place edit to one locus (MS or LS per [isLarge]), preserving
  /// the other locus and the existing segments of the edited locus. Uses the
  /// notification's `cn` as the new change number when present.
  MembershipUpdateResult _applyInPlace(
    Map<String, dynamic> payload,
    String matchingKey,
    bool isLarge, {
    List<String> add = const [],
    List<String> remove = const [],
  }) {
    final ms = _store.mySegmentsForKey(matchingKey);
    final ls = _store.largeSegmentsForKey(matchingKey);
    final target = isLarge ? ls : ms;

    target
      ..addAll(add)
      ..removeAll(remove);

    final cn = payload['cn'];
    final changeNumber = cn is int ? cn : _store.changeNumber(matchingKey);

    _store.applyMembership(
      matchingKey,
      MembershipChange(
        changeNumber: changeNumber,
        mySegments: ms,
        largeSegments: ls,
      ),
    );
    return MembershipUpdateResult._applied;
  }

  static List<String> _names(Map<String, dynamic> payload) {
    final n = payload['n'];
    if (n is! List) return const [];
    return n.whereType<String>().toList(growable: false);
  }
}
