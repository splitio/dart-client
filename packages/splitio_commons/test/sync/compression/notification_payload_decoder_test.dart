import 'dart:convert';
import 'dart:typed_data';

import 'package:splitio_commons/src/sync/compression/compression_type.dart';
import 'package:splitio_commons/src/sync/compression/decompressor.dart';
import 'package:splitio_commons/src/sync/compression/notification_payload_decoder.dart';
import 'package:test/test.dart';

import 'inflate_vectors.dart';

void main() {
  const decoder = NotificationPayloadDecoder();

  String b64(List<int> bytes) => base64.encode(bytes);

  group('c == 0', () {
    test('bytes returns the base64-decoded bytes', () {
      expect(decoder.bytes(0, b64([1, 2, 3, 255])),
          Uint8List.fromList([1, 2, 3, 255]));
    });

    test('text returns the UTF-8 decoded string (non-ASCII)', () {
      const s = 'é ✓';
      expect(decoder.text(0, b64(utf8.encode(s))), s);
    });
  });

  group('compressed payloads', () {
    test('c == 1 inflates gzip', () {
      expect(decoder.bytes(1, jsKeyListGzip), base64.decode(jsKeyListJson));
      expect(decoder.text(1, jsKeyListGzip),
          utf8.decode(base64.decode(jsKeyListJson)));
    });

    test('c == 2 inflates zlib', () {
      expect(decoder.bytes(2, jsBitmap1Zlib), base64.decode(jsBitmap1Plain));
    });

    test('accepts base64 without = padding', () {
      expect(jsKeyListGzip.endsWith('='), isTrue);
      final unpadded = jsKeyListGzip.replaceAll('=', '');
      expect(decoder.bytes(1, unpadded), base64.decode(jsKeyListJson));
      expect(decoder.bytes(0, 'AQI'), Uint8List.fromList([1, 2]));
    });

    test('malformed compressed data throws DecompressionException', () {
      expect(() => decoder.bytes(1, malformedBounded),
          throwsA(isA<DecompressionException>()));
      expect(() => decoder.text(2, b64([1, 2, 3, 4, 5, 6])),
          throwsA(isA<DecompressionException>()));
    });

    test('a custom Decompressor is used and its exceptions pass through', () {
      const failing = NotificationPayloadDecoder(decompressor: _Failing());
      expect(() => failing.bytes(1, b64([1])),
          throwsA(isA<DecompressionException>()));
    });
  });

  group('throws FormatException', () {
    final valid = b64(utf8.encode('hello'));

    for (final c in <Object?>[3, -1, null, '0', '1', 1.0]) {
      test('for unsupported c=$c', () {
        expect(() => decoder.bytes(c, valid), throwsFormatException);
        expect(() => decoder.text(c, valid), throwsFormatException);
      });
    }

    test('for empty d', () {
      expect(() => decoder.bytes(0, ''), throwsFormatException);
      expect(() => decoder.text(0, ''), throwsFormatException);
    });

    for (final d in <Object?>[null, 42]) {
      test('for non-String d=$d', () {
        expect(() => decoder.bytes(0, d), throwsFormatException);
        expect(() => decoder.text(0, d), throwsFormatException);
      });
    }

    test('for invalid base64', () {
      expect(() => decoder.bytes(0, '!!not base64!!'), throwsFormatException);
      expect(() => decoder.text(0, '!!not base64!!'), throwsFormatException);
    });

    test('for invalid UTF-8 in text', () {
      final d = b64([0xC3, 0x28]);
      expect(() => decoder.text(0, d), throwsFormatException);
      // bytes() does not care about UTF-8 validity.
      expect(decoder.bytes(0, d), Uint8List.fromList([0xC3, 0x28]));
    });
  });
}

class _Failing implements Decompressor {
  const _Failing();

  @override
  Uint8List decode(Uint8List bytes, CompressionType type) =>
      throw const DecompressionException('boom');
}
