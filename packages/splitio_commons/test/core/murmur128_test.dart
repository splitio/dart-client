import 'package:splitio_commons/src/core/core.dart';
import 'package:test/test.dart';

void main() {
  group(
      'murmurHash3X64128High — validated against a reference '
      'MurmurHash3_x64_128 (seed 0, high word)', () {
    // Reference values computed with an independent Python
    // MurmurHash3_x64_128 implementation (seed 0), taking the high 64-bit
    // word h1 as an unsigned decimal string. These are the values the server's
    // hashing.Sum128(key) high word produces.
    const vectors = <String, String>{
      '': '0',
      'a': '9607679276477937801',
      'hello': '14688674573012802306',
      'test': '12429135405209477533',
      'key-1234567890': '10455095220724922466',
      'foobar': '13678186819014384197',
      // 17 bytes — exercises the 16-byte block loop plus a 1-byte tail.
      'aaaaaaaaaaaaaaaaa': '8030503933958084248',
    };

    vectors.forEach((key, expectedDec) {
      test('"$key" -> $expectedDec', () {
        expect(murmurHash3X64128High(key).toDecimalString(), expectedDec);
      });
    });

    test('lo is the low 32 bits of the high word', () {
      // hello high word = 14688674573012802306; low 32 bits = 1102945026.
      expect(murmurHash3X64128High('hello').lo, 1102945026);
    });
  });

  group(
      'U64.toDecimalString — hex/binary -> decimal, no BigInt, no precision '
      'loss', () {
    test('zero', () {
      expect(const U64(0, 0).toDecimalString(), '0');
    });
    test('small', () {
      expect(const U64(1, 0).toDecimalString(), '1');
      expect(const U64(42, 0).toDecimalString(), '42');
    });
    test('2^32', () {
      expect(const U64(0, 1).toDecimalString(), '4294967296');
    });
    test('2^53 + 1 (beyond exact JS double integer range)', () {
      // 2^53 = 0x20000000000000 -> hi=0x200000, lo=0. +1 -> lo=1.
      expect(const U64(1, 0x200000).toDecimalString(), '9007199254740993');
    });
    test('2^63', () {
      expect(const U64(0, 0x80000000).toDecimalString(), '9223372036854775808');
    });
    test('2^64 - 1 (max unsigned)', () {
      expect(const U64(0xFFFFFFFF, 0xFFFFFFFF).toDecimalString(),
          '18446744073709551615');
    });
  });
}
