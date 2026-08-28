import 'dart:convert';

import 'package:splitio_commons/src/core/core.dart';

/// The action a key-list membership notification implies for a given key
/// (spec §12.3): add the names to the key's membership, remove them, or nothing.
enum KeyListAction { add, remove, none }

/// Pure membership-payload algorithms (spec §12.3): key hashing, bounded-bitmap
/// membership test, and key-list ADD/REMOVE resolution. Zero I/O, zero store
/// access; decompression of the `d` field is the caller's responsibility — this
/// operates on already-decoded byte arrays / JSON text.
///
/// All arithmetic is `BigInt`-free so a single implementation runs identically
/// on the Dart VM and on Flutter Web (see [murmurHash3X64128High]).
class MembershipPayloadDecoder {
  const MembershipPayloadDecoder();

  /// The full 64-bit high word of `MurmurHash3.hash128x64(utf8(key))` as an
  /// unsigned canonical **decimal string** — the key-list comparison value.
  /// Matches the server's `hashing.Sum128(key)` high word.
  String hashKeyDecimal(String matchingKey) =>
      murmurHash3X64128High(matchingKey).toDecimalString();

  /// The low 32 bits of the hashed key — all the bounded-bitmap path needs
  /// (the bitmap size is a power of two, so `lo32 mod m == hashedKey mod m`).
  int hashKeyLow32(String matchingKey) => murmurHash3X64128High(matchingKey).lo;

  /// Bounded-bitmap membership test (spec §12.3). `keyMap` is the raw
  /// (already-decompressed) byte array; `FIELD_SIZE = 8` bits/byte. Returns
  /// `true` when the user is targeted (perform the fetch).
  bool isInBitmap(int hashedKeyLow32, List<int> keyMap) {
    if (keyMap.isEmpty) return false;
    final lo32 = hashedKeyLow32 & 0xFFFFFFFF;
    final index = lo32 % (keyMap.length * 8);
    final internal = index ~/ 8;
    final offset = index % 8;
    if (internal > keyMap.length - 1) return false;
    return (keyMap[internal] & (1 << offset)) != 0;
  }

  /// Resolves the key-list action for the given decimal-string hashed key
  /// against the ADD (`a`) and REMOVE (`r`) arrays (spec §12.3). Entries are
  /// compared as raw decimal strings — never numerically parsed — to keep full
  /// 64-bit precision without `BigInt`.
  KeyListAction resolveKeyListAction(
    String hashedKeyDecimal, {
    required List<String> a,
    required List<String> r,
  }) {
    if (a.contains(hashedKeyDecimal)) return KeyListAction.add;
    if (r.contains(hashedKeyDecimal)) return KeyListAction.remove;
    return KeyListAction.none;
  }

  /// Digit-preserving parse of a key-list JSON payload `{"a":[...],"r":[...]}`.
  ///
  /// The server emits hashed keys as raw 64-bit integers that exceed 2^53, so
  /// decoding them as JSON numbers would lose precision on Flutter Web. Like the
  /// JS SDK (`parseUtils.ts#parseKeyList`), each bare integer is wrapped in
  /// quotes (`\d+` → `"\d+"`) before decoding, so every `a`/`r` entry survives
  /// as its exact decimal string.
  ({List<String> a, List<String> r}) parseKeyList(String jsonText) {
    final wrapped =
        jsonText.replaceAllMapped(RegExp(r'\d+'), (m) => '"${m[0]}"');
    final decoded = json.decode(wrapped);
    if (decoded is! Map) return (a: const [], r: const []);
    return (a: _stringList(decoded['a']), r: _stringList(decoded['r']));
  }

  static List<String> _stringList(Object? v) {
    if (v is! List) return const [];
    return v.map((e) => e.toString()).toList(growable: false);
  }
}
