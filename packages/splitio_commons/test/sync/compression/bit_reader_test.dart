import 'dart:typed_data';

import 'package:splitio_commons/src/sync/compression/bit_reader.dart';
import 'package:splitio_commons/src/sync/compression/decompressor.dart';
import 'package:test/test.dart';

void main() {
  group('BitReader', () {
    test('reads LSB first across byte boundaries', () {
      final r = BitReader(Uint8List.fromList([0xA5, 0x3C]), 0);
      expect(r.read(1), 1);
      expect(r.read(3), 2); // bits 1..3 of 0xA5 (1010 0101) = 010
      expect(r.read(8), 0xCA); // spans both bytes
      expect(r.read(4), 0x3);
    });

    test('peek does not consume', () {
      final r = BitReader(Uint8List.fromList([0xFF, 0x01]), 0);
      expect(r.peek(9), 0x1FF);
      expect(r.peek(9), 0x1FF);
      expect(r.read(9), 0x1FF);
    });

    test('reads 16 bits at an unaligned position', () {
      final r = BitReader(Uint8List.fromList([0xFF, 0xFF, 0xFF]), 0);
      r.skip(7);
      expect(r.read(16), 0xFFFF);
    });

    test('peek zero-fills past the end, skip throws', () {
      final r = BitReader(Uint8List.fromList([0x01]), 0);
      expect(r.peek(16), 1);
      expect(() => r.skip(9), throwsA(isA<DecompressionException>()));
    });

    test('read exactly to the end is fine, one more bit throws', () {
      final r = BitReader(Uint8List.fromList([0x00]), 0);
      r.read(8);
      expect(() => r.read(1), throwsA(isA<DecompressionException>()));
    });

    test('alignedByteOffset and seekByte', () {
      final r = BitReader(Uint8List(4), 1);
      expect(r.alignedByteOffset, 1);
      r.skip(3);
      expect(r.alignedByteOffset, 2);
      r.seekByte(4);
      expect(r.alignedByteOffset, 4);
      expect(() => r.seekByte(5), throwsA(isA<DecompressionException>()));
    });
  });
}
