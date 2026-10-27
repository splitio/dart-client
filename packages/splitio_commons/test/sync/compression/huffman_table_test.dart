import 'dart:typed_data';

import 'package:splitio_commons/src/sync/compression/bit_reader.dart';
import 'package:splitio_commons/src/sync/compression/decompressor.dart';
import 'package:splitio_commons/src/sync/compression/huffman_table.dart';
import 'package:test/test.dart';

void main() {
  group('HuffmanTable', () {
    test('decodes canonical codes (RFC 1951 §3.2.2 example)', () {
      // Lengths (3,3,3,3,3,2,4,4) for symbols A..H give:
      // A=010 B=011 C=100 D=101 E=110 F=00 G=1110 H=1111.
      final t = HuffmanTable.fromLengths(
          Uint8List.fromList([3, 3, 3, 3, 3, 2, 4, 4]));
      expect(t.maxBits, 4);
      // Codes are packed MSB-first into the LSB-first stream:
      // F(00) A(010) H(1111) -> bits 0,0, 0,1,0, 1,1,1,1.
      final bits = [0, 0, 0, 1, 0, 1, 1, 1, 1];
      final bytes = Uint8List(2);
      for (var i = 0; i < bits.length; i++) {
        bytes[i >> 3] |= bits[i] << (i & 7);
      }
      final r = BitReader(bytes, 0);
      expect([t.decode(r), t.decode(r), t.decode(r)], [5, 0, 7]);
    });

    test('fixed tables have the documented sizes', () {
      expect(HuffmanTable.fixedLiteral.maxBits, 9);
      expect(HuffmanTable.fixedDistance.maxBits, 5);
    });

    test('over-subscribed lengths throw', () {
      expect(() => HuffmanTable.fromLengths(Uint8List.fromList([1, 1, 1])),
          throwsA(isA<DecompressionException>()));
    });

    test('incomplete code is accepted but its unused code throws', () {
      final t = HuffmanTable.fromLengths(Uint8List.fromList([1]));
      expect(t.decode(BitReader(Uint8List.fromList([0]), 0)), 0);
      expect(() => t.decode(BitReader(Uint8List.fromList([1]), 0)),
          throwsA(isA<DecompressionException>()));
    });

    test('empty table throws on any decode', () {
      final t = HuffmanTable.fromLengths(Uint8List(4));
      expect(t.maxBits, 0);
      expect(() => t.decode(BitReader(Uint8List(1), 0)),
          throwsA(isA<DecompressionException>()));
    });

    test('truncated code throws', () {
      final t = HuffmanTable.fromLengths(Uint8List.fromList([2, 2, 2, 2]));
      final r = BitReader(Uint8List(1), 0)..skip(7);
      expect(() => t.decode(r), throwsA(isA<DecompressionException>()));
    });
  });
}
