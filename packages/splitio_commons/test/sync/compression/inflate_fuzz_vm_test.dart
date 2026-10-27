@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:splitio_commons/src/sync/compression/compression_type.dart';
import 'package:splitio_commons/src/sync/compression/decompressor.dart';
import 'package:splitio_commons/src/sync/compression/inflate_decompressor.dart';
import 'package:test/test.dart';

/// VM-only round-trip and fuzz tests against dart:io's gzip/zlib codecs.
void main() {
  const inflate = InflateDecompressor();
  final rnd = Random(20261019);

  Uint8List randomInput() {
    final n = rnd.nextInt(5000);
    final alphabet = 1 + rnd.nextInt(256);
    final bytes = Uint8List(n);
    for (var i = 0; i < n; i++) {
      bytes[i] = rnd.nextInt(alphabet);
    }
    // Sprinkle repeats so back-references are exercised.
    for (var i = 0; i < n ~/ 10 && n > 20; i++) {
      final from = rnd.nextInt(n - 10);
      final to = rnd.nextInt(n - 10);
      bytes.setRange(to, to + 8, bytes, from);
    }
    return bytes;
  }

  test('round-trips random inputs at every compression level', () {
    for (var i = 0; i < 300; i++) {
      final data = randomInput();
      final level = rnd.nextInt(10);
      final gz = Uint8List.fromList(GZipCodec(level: level).encode(data));
      final zl = Uint8List.fromList(ZLibCodec(level: level).encode(data));
      expect(inflate.decode(gz, CompressionType.gzip), data);
      expect(inflate.decode(zl, CompressionType.zlib), data);
    }
  });

  test('round-trips large and highly repetitive inputs', () {
    final data = Uint8List(3 * 1024 * 1024);
    for (var i = 0; i < data.length; i++) {
      data[i] = (i ~/ 7) & 0xFF;
    }
    final gz = Uint8List.fromList(gzip.encode(data));
    expect(inflate.decode(gz, CompressionType.gzip), data);
  });

  test('corrupted streams only ever throw DecompressionException', () {
    for (var i = 0; i < 2000; i++) {
      final data = randomInput();
      final good = Uint8List.fromList(
          rnd.nextBool() ? gzip.encode(data) : zlib.encode(data));
      final type =
          good[0] == 0x1f ? CompressionType.gzip : CompressionType.zlib;
      final bad = Uint8List.fromList(good);
      for (var k = 0; k < 1 + rnd.nextInt(3); k++) {
        bad[rnd.nextInt(bad.length)] ^= 1 << rnd.nextInt(8);
      }
      final cut = rnd.nextBool()
          ? bad
          : Uint8List.sublistView(bad, 0, rnd.nextInt(bad.length));
      try {
        inflate.decode(cut, type);
      } on DecompressionException {
        // expected
      }
    }
  });

  test('random garbage never hangs or throws another error', () {
    for (var i = 0; i < 2000; i++) {
      final junk = Uint8List.fromList(
          List<int>.generate(rnd.nextInt(200), (_) => rnd.nextInt(256)));
      for (final type in [CompressionType.gzip, CompressionType.zlib]) {
        try {
          inflate.decode(junk, type);
        } on DecompressionException {
          // expected
        }
      }
    }
  });
}
