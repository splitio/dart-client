/// Compression byte `c` on streaming payloads (spec §12.3, Appendix A.1).
enum CompressionType {
  none,
  gzip,
  zlib;

  /// `0`->none, `1`->gzip, `2`->zlib; anything else (including non-int) ->
  /// null, which callers MUST treat as "drop + fetch" (spec §12.3).
  static CompressionType? fromWire(Object? c) {
    if (c is! int) return null;
    switch (c) {
      case 0:
        return CompressionType.none;
      case 1:
        return CompressionType.gzip;
      case 2:
        return CompressionType.zlib;
      default:
        return null;
    }
  }
}
