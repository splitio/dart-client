import 'dart:convert';
import 'dart:typed_data';

import 'compression_type.dart';
import 'decompressor.dart';
import 'inflate_decompressor.dart';

/// Turns the `(c, d)` pair of a streaming notification payload into bytes or
/// text (spec §12.3: always base64 -> decompress).
///
/// `c` is `0` (none), `1` (gzip) or `2` (zlib); any other value throws
/// [FormatException]. The base64 text is accepted with or without `=` padding.
/// Malformed compressed input surfaces as [DecompressionException]. Callers
/// turn any throw into a fetch fallback.
class NotificationPayloadDecoder {
  final Decompressor _decompressor;

  const NotificationPayloadDecoder({
    Decompressor decompressor = const InflateDecompressor(),
  }) : _decompressor = decompressor;

  /// base64-decodes [d] then decompresses it per compression byte [c].
  /// Throws [FormatException] when [c] is unsupported, [d] is not a non-empty
  /// String, or [d] is not valid base64; [DecompressionException] when the
  /// compressed bytes are malformed.
  Uint8List bytes(Object? c, Object? d) {
    final type = CompressionType.fromWire(c);
    if (type == null) {
      throw FormatException('Unsupported compression: $c');
    }
    if (d is! String || d.isEmpty) {
      throw const FormatException('Payload data must be a non-empty string');
    }
    final raw = base64.decode(base64.normalize(d));
    return _decompressor.decode(raw, type);
  }

  /// [bytes] then strict UTF-8 decode (`allowMalformed: false`).
  String text(Object? c, Object? d) =>
      utf8.decode(bytes(c, d), allowMalformed: false);
}
