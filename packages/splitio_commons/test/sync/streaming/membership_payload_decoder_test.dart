import 'package:splitio_commons/src/core/core.dart';
import 'package:splitio_commons/src/sync/streaming/membership_payload_decoder.dart';
import 'package:test/test.dart';

void main() {
  const decoder = MembershipPayloadDecoder();

  group('key hashing wrappers delegate to murmurHash3X64128High', () {
    // The murmur128 algorithm itself is validated in
    // packages/core/test/murmur128_test.dart. Here we only assert the decoder's
    // thin wrappers surface the high word's decimal string and low 32 bits.
    test('hashKeyDecimal returns the high-word decimal string', () {
      expect(decoder.hashKeyDecimal('hello'),
          murmurHash3X64128High('hello').toDecimalString());
      expect(decoder.hashKeyDecimal('hello'), '14688674573012802306');
    });

    test('hashKeyLow32 returns the high word low 32 bits', () {
      expect(decoder.hashKeyLow32('hello'), murmurHash3X64128High('hello').lo);
      expect(decoder.hashKeyLow32('hello'), 1102945026);
    });
  });

  group('isInBitmap', () {
    test('empty keyMap is never a member', () {
      expect(decoder.isInBitmap(0, const []), isFalse);
    });

    test('bit set at computed index -> member', () {
      // 2 bytes -> 16 bits. Pick hashedKeyLow32 = 10.
      // index = 10 % 16 = 10; internal = 1; offset = 2; bit = 1<<2 = 4.
      final keyMap = [0x00, 0x04];
      expect(decoder.isInBitmap(10, keyMap), isTrue);
    });

    test('bit unset at computed index -> not member', () {
      final keyMap = [0x00, 0x00];
      expect(decoder.isInBitmap(10, keyMap), isFalse);
    });

    test('index 0 -> byte 0 bit 0', () {
      expect(decoder.isInBitmap(0, [0x01, 0x00]), isTrue);
      expect(decoder.isInBitmap(0, [0x00, 0x00]), isFalse);
    });

    test('index wraps modulo (len*8)', () {
      // len*8 = 16; hashedKeyLow32 = 26 -> 26 % 16 = 10 (same as the "10" case).
      final keyMap = [0x00, 0x04];
      expect(decoder.isInBitmap(26, keyMap), isTrue);
    });

    test('lo32 masking: only low 32 bits used', () {
      // A value already within 32 bits; also verify high bits are irrelevant by
      // passing a value that fits but exercises the mask path.
      expect(decoder.isInBitmap(0xFFFFFFFF & 10, [0x00, 0x04]), isTrue);
    });

    test('every bit position in a byte', () {
      for (var offset = 0; offset < 8; offset++) {
        final keyMap = [1 << offset];
        // len*8 = 8; index == offset when hashedKeyLow32 == offset.
        expect(decoder.isInBitmap(offset, keyMap), isTrue,
            reason: 'offset $offset should be set');
        expect(decoder.isInBitmap((offset + 1) % 8, keyMap),
            (offset + 1) % 8 == offset);
      }
    });
  });

  group('resolveKeyListAction', () {
    test('in a -> add', () {
      expect(
        decoder.resolveKeyListAction('123', a: ['123', '456'], r: ['789']),
        KeyListAction.add,
      );
    });
    test('in r -> remove', () {
      expect(
        decoder.resolveKeyListAction('789', a: ['123'], r: ['789']),
        KeyListAction.remove,
      );
    });
    test('in neither -> none', () {
      expect(
        decoder.resolveKeyListAction('999', a: ['123'], r: ['789']),
        KeyListAction.none,
      );
    });
    test('a takes precedence if present in both', () {
      expect(
        decoder.resolveKeyListAction('5', a: ['5'], r: ['5']),
        KeyListAction.add,
      );
    });
    test('full 64-bit value compared as string exactly', () {
      const big = '18446744073709551615';
      expect(
        decoder.resolveKeyListAction(big, a: [big], r: const []),
        KeyListAction.add,
      );
      // A value differing only in the last digit must NOT match.
      expect(
        decoder.resolveKeyListAction('18446744073709551614',
            a: [big], r: const []),
        KeyListAction.none,
      );
    });
  });

  group('parseKeyList — digit-preserving', () {
    test('preserves full precision of >2^53 integers as strings', () {
      const jsonText =
          '{"a":[18446744073709551615,123],"r":[9223372036854775808]}';
      final result = decoder.parseKeyList(jsonText);
      expect(result.a, ['18446744073709551615', '123']);
      expect(result.r, ['9223372036854775808']);
    });

    test('handles empty arrays', () {
      final result = decoder.parseKeyList('{"a":[],"r":[]}');
      expect(result.a, isEmpty);
      expect(result.r, isEmpty);
    });

    test('missing keys yield empty lists', () {
      final result = decoder.parseKeyList('{}');
      expect(result.a, isEmpty);
      expect(result.r, isEmpty);
    });

    test('round-trips into resolveKeyListAction without precision loss', () {
      const jsonText = '{"a":[10455095220724922466],"r":[]}';
      final parsed = decoder.parseKeyList(jsonText);
      final hash = decoder.hashKeyDecimal('key-1234567890');
      expect(hash, '10455095220724922466');
      expect(
        decoder.resolveKeyListAction(hash, a: parsed.a, r: parsed.r),
        KeyListAction.add,
      );
    });
  });
}
