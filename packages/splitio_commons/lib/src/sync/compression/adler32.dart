import 'dart:typed_data';

/// Adler-32 checksum (RFC 1950 §8.2, as used by zlib).
class Adler32 {
  static const int _mod = 65521;
  // Largest block for which the sums cannot exceed 2^32 before reduction.
  static const int _block = 5552;

  /// Returns the Adler-32 of [data] as an unsigned 32-bit integer.
  static int of(Uint8List data) {
    var a = 1;
    var b = 0;
    var i = 0;
    while (i < data.length) {
      final end = i + _block < data.length ? i + _block : data.length;
      for (; i < end; i++) {
        a += data[i];
        b += a;
      }
      a %= _mod;
      b %= _mod;
    }
    return b * 65536 + a;
  }
}
