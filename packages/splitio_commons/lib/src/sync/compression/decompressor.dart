import 'dart:typed_data';

import 'compression_type.dart';

/// Axis-1 platform SPI (spec §2, §6). Inflates gzip / zlib byte streams.
///
/// Implementations MUST be synchronous, MUST be pure Dart (available on every
/// target), and MUST signal any malformed input by throwing
/// [DecompressionException].
abstract interface class Decompressor {
  /// Returns the decompressed [bytes] for [type]. [CompressionType.none]
  /// returns [bytes] unchanged.
  Uint8List decode(Uint8List bytes, CompressionType type);
}

/// Thrown when compressed input is malformed, truncated, fails a checksum or
/// would inflate past the configured output limit.
class DecompressionException implements Exception {
  /// Human-readable reason.
  final String message;

  const DecompressionException(this.message);

  @override
  String toString() => 'DecompressionException: $message';
}
