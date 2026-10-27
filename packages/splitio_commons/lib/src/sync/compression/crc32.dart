import 'dart:typed_data';

/// Table-based CRC-32 (IEEE 802.3, as used by gzip). Web safe: every value is
/// kept in `[0, 2^32)` with explicit masks.
class Crc32 {
  static final Uint32List _table = _buildTable();

  static Uint32List _buildTable() {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      t[n] = c & 0xFFFFFFFF;
    }
    return t;
  }

  /// Returns the CRC-32 of [data] as an unsigned 32-bit integer.
  static int of(Uint8List data) {
    var c = 0xFFFFFFFF;
    for (var i = 0; i < data.length; i++) {
      c = (_table[(c ^ data[i]) & 0xFF] ^ (c >>> 8)) & 0xFFFFFFFF;
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
