import 'dart:convert';
import 'dart:typed_data';

import 'package:splitio_commons/src/sync/compression/adler32.dart';
import 'package:splitio_commons/src/sync/compression/crc32.dart';
import 'package:test/test.dart';

Uint8List _ascii(String s) => Uint8List.fromList(ascii.encode(s));

void main() {
  group('Crc32', () {
    test('empty input is 0', () => expect(Crc32.of(Uint8List(0)), 0));

    test('standard check value', () {
      expect(Crc32.of(_ascii('123456789')), 0xCBF43926);
    });

    test('result is unsigned 32-bit for high-bit values', () {
      // CRC-32 of "a" is 0xE8B7BE43 (top bit set).
      expect(Crc32.of(_ascii('a')), 0xE8B7BE43);
    });

    test('handles all byte values', () {
      final all = Uint8List.fromList(List<int>.generate(256, (i) => i));
      expect(Crc32.of(all), 0x29058C73);
    });
  });

  group('Adler32', () {
    test('empty input is 1', () => expect(Adler32.of(Uint8List(0)), 1));

    test('known values', () {
      expect(Adler32.of(_ascii('Wikipedia')), 0x11E60398);
      expect(Adler32.of(_ascii('a')), 0x00620062);
    });

    test('long input crosses the reduction block size', () {
      // 0xFF bytes maximise the sums; value computed with zlib.adler32.
      expect(Adler32.of(Uint8List(100000)..fillRange(0, 100000, 0xFF)),
          0x149A302C);
    });
  });
}
