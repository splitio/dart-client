import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/storage/storage.dart';

import '../compression/notification_payload_decoder.dart';
import 'membership_payload_decoder.dart';
import 'notification_processor.dart';

/// The result of a single [MembershipUpdateStrategy.handle] call (spec §12.2).
///
/// [fetchRequired] means the caller (StreamingManager, task 4.7) MUST trigger an
/// **unbounded** full memberships fetch for the user key — either because the
/// strategy mandates it, the payload could not be decoded, or in-place apply
/// was not safe. [didApplyInPlace] records whether the store was mutated directly.
/// [changed] records whether that in-place apply actually added or removed a
/// key from the store (used to drive `whenUpdated()`, spec §4.6/§8.2).
class MembershipUpdateResult {
  final bool fetchRequired;
  final bool didApplyInPlace;
  final bool changed;

  const MembershipUpdateResult({
    required this.fetchRequired,
    required this.didApplyInPlace,
    this.changed = false,
  });

  static const MembershipUpdateResult _fetch = MembershipUpdateResult(
    fetchRequired: true,
    didApplyInPlace: false,
  );

  static const MembershipUpdateResult _noop = MembershipUpdateResult(
    fetchRequired: false,
    didApplyInPlace: false,
  );

  factory MembershipUpdateResult._applied(bool changed) =>
      MembershipUpdateResult(
        fetchRequired: false,
        didApplyInPlace: true,
        changed: changed,
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
/// `d` is decoded through [NotificationPayloadDecoder] (`c` 0 NONE / 1 GZIP /
/// 2 ZLIB). BOUNDED fetches only when the key's bit is set in the bitmap;
/// KEY_LIST is applied in place. A decode error on a non-empty `d` falls back
/// to an unbounded fetch and is logged at WARNING once per notification (the
/// dispatcher calls [handle] once per bound key with the same [FeedUpdate]).
class MembershipUpdateStrategy {
  final MembershipStore _store;
  final MembershipPayloadDecoder _decoder;
  final NotificationPayloadDecoder _payloadDecoder;
  final SplitLogger? _logger;

  /// The last [FeedUpdate] whose decode failure was logged (by identity).
  FeedUpdate? _lastLoggedFailure;

  MembershipUpdateStrategy({
    required MembershipStore store,
    required MembershipPayloadDecoder decoder,
    NotificationPayloadDecoder? payloadDecoder,
    SplitLogger? logger,
  })  : _logger = logger,
        _store = store,
        _decoder = decoder,
        _payloadDecoder = payloadDecoder ?? const NotificationPayloadDecoder();

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
          return _handleBounded(update, matchingKey);
        case 2: // KEY_LIST
          return _handleKeyList(update, matchingKey, isLarge);
        case 3: // SEGMENT_REMOVAL
          return _handleSegmentRemoval(payload, matchingKey, isLarge);
        default:
          return MembershipUpdateResult._fetch;
      }
    } catch (_) {
      return MembershipUpdateResult._fetch;
    }
  }

  /// BOUNDED_FETCH_REQUEST: fetch only when the key's bit is set in the
  /// (decompressed) bitmap; an absent `d` or a decode error falls back to an
  /// unbounded fetch.
  MembershipUpdateResult _handleBounded(FeedUpdate update, String matchingKey) {
    final payload = update.payload;
    final d = payload['d'];
    if (d is! String || d.isEmpty) return MembershipUpdateResult._fetch;

    final List<int> keyMap;
    try {
      keyMap = _payloadDecoder.bytes(payload['c'], d);
    } catch (e) {
      _logDecodeFailure(update, 'BoundedFetchRequest', e);
      return MembershipUpdateResult._fetch;
    }
    return _decoder.isInBitmap(_decoder.hashKeyLow32(matchingKey), keyMap)
        ? MembershipUpdateResult._fetch
        : MembershipUpdateResult._noop;
  }

  MembershipUpdateResult _handleKeyList(
    FeedUpdate update,
    String matchingKey,
    bool isLarge,
  ) {
    final payload = update.payload;
    final d = payload['d'];
    if (d is! String || d.isEmpty) return MembershipUpdateResult._fetch;

    final ({List<String> a, List<String> r}) keyList;
    try {
      keyList = _decoder.parseKeyList(_payloadDecoder.text(payload['c'], d));
    } catch (e) {
      _logDecodeFailure(update, 'KeyList', e);
      return MembershipUpdateResult._fetch;
    }
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

  /// Logs the decode failure of [update] once per notification (identity).
  void _logDecodeFailure(FeedUpdate update, String kind, Object error) {
    if (identical(_lastLoggedFailure, update)) return;
    _lastLoggedFailure = update;
    _logger?.warning('Fetching Memberships due to an error processing $kind '
        'notification: $error');
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

    final changed = _store.applyMembership(
      matchingKey,
      MembershipChange(
        changeNumber: changeNumber,
        mySegments: ms,
        largeSegments: ls,
      ),
    );
    return MembershipUpdateResult._applied(changed);
  }

  static List<String> _names(Map<String, dynamic> payload) {
    final n = payload['n'];
    if (n is! List) return const [];
    return n.whereType<String>().toList(growable: false);
  }
}
