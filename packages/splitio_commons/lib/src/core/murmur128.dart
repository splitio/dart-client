import 'dart:convert';

/// An unsigned 64-bit value represented as two 32-bit halves (`hi`, `lo`).
///
/// This exists so the SDK can compute MurmurHash3 x64/128 **without `BigInt`**:
/// Dart compiled to JS (Flutter Web) has no native 64-bit `int`, and `BigInt`
/// there is heap-allocated and ~1-2 orders of magnitude slower (see spec
/// §12.3). All 64-bit arithmetic below is emulated over 16-bit limbs so every
/// intermediate stays well under 2^53 (safe on JS doubles).
class U64 {
  /// Low 32 bits (always masked to `0xFFFFFFFF`).
  final int lo;

  /// High 32 bits (always masked to `0xFFFFFFFF`).
  final int hi;

  const U64(this.lo, this.hi);

  static const U64 zero = U64(0, 0);

  U64 xor(U64 o) => U64(lo ^ o.lo, hi ^ o.hi);

  /// Adds `o` modulo 2^64.
  U64 add(U64 o) {
    final sum = lo + o.lo; // < 2^33, safe
    final loRes = sum & 0xFFFFFFFF;
    final carry = sum >= 0x100000000 ? 1 : 0;
    final hiRes = (hi + o.hi + carry) & 0xFFFFFFFF;
    return U64(loRes, hiRes);
  }

  /// Multiplies `o` modulo 2^64 using 16-bit limbs (no value exceeds 2^53).
  U64 multiply(U64 o) {
    final a0 = lo & 0xFFFF, a1 = (lo >>> 16) & 0xFFFF;
    final a2 = hi & 0xFFFF, a3 = (hi >>> 16) & 0xFFFF;
    final b0 = o.lo & 0xFFFF, b1 = (o.lo >>> 16) & 0xFFFF;
    final b2 = o.hi & 0xFFFF, b3 = (o.hi >>> 16) & 0xFFFF;

    var c0 = a0 * b0;
    var c1 = a0 * b1 + a1 * b0;
    var c2 = a0 * b2 + a1 * b1 + a2 * b0;
    var c3 = a0 * b3 + a1 * b2 + a2 * b1 + a3 * b0;

    final r0 = c0 & 0xFFFF;
    c1 += c0 >>> 16;
    final r1 = c1 & 0xFFFF;
    c2 += c1 >>> 16;
    final r2 = c2 & 0xFFFF;
    c3 += c2 >>> 16;
    final r3 = c3 & 0xFFFF;

    return U64(r0 | (r1 << 16), r2 | (r3 << 16));
  }

  /// Logical left shift by `n` (0..63) modulo 2^64.
  U64 shl(int n) {
    if (n == 0) return this;
    if (n >= 64) return zero;
    if (n == 32) return U64(0, lo);
    if (n < 32) {
      final newHi = ((hi << n) | (lo >>> (32 - n))) & 0xFFFFFFFF;
      final newLo = (lo << n) & 0xFFFFFFFF;
      return U64(newLo, newHi);
    }
    // 32 < n < 64
    return U64(0, (lo << (n - 32)) & 0xFFFFFFFF);
  }

  /// Logical (unsigned) right shift by `n` (0..63).
  U64 shr(int n) {
    if (n == 0) return this;
    if (n >= 64) return zero;
    if (n == 32) return U64(hi, 0);
    if (n < 32) {
      final newLo = ((lo >>> n) | (hi << (32 - n))) & 0xFFFFFFFF;
      final newHi = hi >>> n;
      return U64(newLo, newHi);
    }
    // 32 < n < 64
    return U64(hi >>> (n - 32), 0);
  }

  /// Rotates left by `r` (1..63) — the only forms MurmurHash uses.
  U64 rotl(int r) => shl(r).or(shr(64 - r));

  U64 or(U64 o) => U64(lo | o.lo, hi | o.hi);

  U64 operator &(U64 o) => U64(lo & o.lo, hi & o.hi);

  /// Renders this value as an unsigned canonical decimal string, with no
  /// `BigInt` — long division by 10 over base-2^16 limbs (spec §12.3 requires
  /// the key-list hash as a decimal string to survive on Flutter Web).
  String toDecimalString() {
    // Limbs most-significant first, base 65536.
    var limbs = <int>[
      (hi >>> 16) & 0xFFFF,
      hi & 0xFFFF,
      (lo >>> 16) & 0xFFFF,
      lo & 0xFFFF,
    ];
    final digits = <int>[];
    // Repeatedly divide the whole number by 10 collecting remainders.
    while (limbs.any((l) => l != 0)) {
      var rem = 0;
      final next = <int>[];
      for (final limb in limbs) {
        final cur = rem * 65536 + limb; // < 2^20, safe
        next.add(cur ~/ 10);
        rem = cur % 10;
      }
      digits.add(rem);
      // Trim leading zero limbs to keep the loop bounded.
      limbs = next;
    }
    if (digits.isEmpty) return '0';
    return digits.reversed.join();
  }
}

/// MurmurHash3 x64/128 — returns the **high 64-bit word** (`h1`) as a [U64].
///
/// This matches the server's `hashing.Sum128(key)` high word and the value the
/// bounded-bitmap / key-list membership algorithms hash against (spec §12.3).
/// Computed without `BigInt`; both `h1` and `h2` are tracked internally because
/// the x64/128 mixing intertwines them, but only `h1` is returned.
U64 murmurHash3X64128High(String key, [int seed = 0]) {
  final data = utf8.encode(key);
  final len = data.length;
  final nblocks = len ~/ 16;

  final c1 = const U64(0x114253d5, 0x87c37b91);
  final c2 = const U64(0x2745937f, 0x4cf5ad43);

  var h1 = U64(seed & 0xFFFFFFFF, 0);
  var h2 = U64(seed & 0xFFFFFFFF, 0);

  U64 readLe64(int off) {
    final lo = data[off] |
        (data[off + 1] << 8) |
        (data[off + 2] << 16) |
        ((data[off + 3] << 24) & 0xFFFFFFFF);
    final hi = data[off + 4] |
        (data[off + 5] << 8) |
        (data[off + 6] << 16) |
        ((data[off + 7] << 24) & 0xFFFFFFFF);
    return U64(lo & 0xFFFFFFFF, hi & 0xFFFFFFFF);
  }

  for (var i = 0; i < nblocks; i++) {
    final base = i * 16;
    var k1 = readLe64(base);
    var k2 = readLe64(base + 8);

    k1 = k1.multiply(c1).rotl(31).multiply(c2);
    h1 = h1.xor(k1);
    h1 = h1.rotl(27).add(h2);
    h1 = h1.multiply(const U64(5, 0)).add(const U64(0x52dce729, 0));

    k2 = k2.multiply(c2).rotl(33).multiply(c1);
    h2 = h2.xor(k2);
    h2 = h2.rotl(31).add(h1);
    h2 = h2.multiply(const U64(5, 0)).add(const U64(0x38495ab5, 0));
  }

  // Tail
  final tail = nblocks * 16;
  var k1 = U64.zero;
  var k2 = U64.zero;
  final rem = len & 15;

  if (rem >= 15) k2 = k2.xor(U64(0, 0).or(_byteAt(data, tail + 14, 48)));
  if (rem >= 14) k2 = k2.xor(_byteAt(data, tail + 13, 40));
  if (rem >= 13) k2 = k2.xor(_byteAt(data, tail + 12, 32));
  if (rem >= 12) k2 = k2.xor(_byteAt(data, tail + 11, 24));
  if (rem >= 11) k2 = k2.xor(_byteAt(data, tail + 10, 16));
  if (rem >= 10) k2 = k2.xor(_byteAt(data, tail + 9, 8));
  if (rem >= 9) {
    k2 = k2.xor(_byteAt(data, tail + 8, 0));
    k2 = k2.multiply(c2).rotl(33).multiply(c1);
    h2 = h2.xor(k2);
  }

  if (rem >= 8) k1 = k1.xor(_byteAt(data, tail + 7, 56));
  if (rem >= 7) k1 = k1.xor(_byteAt(data, tail + 6, 48));
  if (rem >= 6) k1 = k1.xor(_byteAt(data, tail + 5, 40));
  if (rem >= 5) k1 = k1.xor(_byteAt(data, tail + 4, 32));
  if (rem >= 4) k1 = k1.xor(_byteAt(data, tail + 3, 24));
  if (rem >= 3) k1 = k1.xor(_byteAt(data, tail + 2, 16));
  if (rem >= 2) k1 = k1.xor(_byteAt(data, tail + 1, 8));
  if (rem >= 1) {
    k1 = k1.xor(_byteAt(data, tail, 0));
    k1 = k1.multiply(c1).rotl(31).multiply(c2);
    h1 = h1.xor(k1);
  }

  // Finalization
  final lenU = U64(len & 0xFFFFFFFF, 0);
  h1 = h1.xor(lenU);
  h2 = h2.xor(lenU);
  h1 = h1.add(h2);
  h2 = h2.add(h1);
  h1 = _fmix64(h1);
  h2 = _fmix64(h2);
  h1 = h1.add(h2);
  // h2 = h2.add(h1); // not needed: only h1 (high word) is returned.

  return h1;
}

U64 _byteAt(List<int> data, int index, int shift) =>
    U64(data[index] & 0xFF, 0).shl(shift);

U64 _fmix64(U64 k) {
  k = k.xor(k.shr(33));
  k = k.multiply(const U64(0xed558ccd, 0xff51afd7));
  k = k.xor(k.shr(33));
  k = k.multiply(const U64(0x1a85ec53, 0xc4ceb9fe));
  k = k.xor(k.shr(33));
  return k;
}
