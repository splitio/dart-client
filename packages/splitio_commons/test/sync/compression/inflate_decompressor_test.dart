import 'dart:convert';
import 'dart:typed_data';

import 'package:splitio_commons/src/sync/compression/compression_type.dart';
import 'package:splitio_commons/src/sync/compression/decompressor.dart';
import 'package:splitio_commons/src/sync/compression/inflate_decompressor.dart';
import 'package:test/test.dart';

import 'inflate_vectors.dart';

Uint8List _b(String b64) => base64.decode(base64.normalize(b64));

Matcher get _throwsDecompression => throwsA(isA<DecompressionException>());

void main() {
  const inflate = InflateDecompressor();
  Uint8List gunzip(String d) => inflate.decode(_b(d), CompressionType.gzip);
  Uint8List unzlib(String d) => inflate.decode(_b(d), CompressionType.zlib);

  group('block types', () {
    test('stored', () {
      expect(gunzip(storedGzip), _b(storedPlain));
      expect(unzlib(storedZlib), _b(storedPlain));
    });

    test('fixed Huffman', () {
      expect(gunzip(fixedGzip), _b(fixedPlain));
      expect(unzlib(fixedZlib), _b(fixedPlain));
    });

    test('dynamic Huffman', () {
      expect(gunzip(dynamicGzip), _b(dynamicPlain));
      expect(unzlib(dynamicZlib), _b(dynamicPlain));
    });

    test('dynamic block with an incomplete distance tree', () {
      expect(unzlib(incompleteDistValidZlib), _b(incompleteDistValidPlain));
    });

    test('multiple blocks (full flush between chunks, empty chunk)', () {
      expect(gunzip(multiGzip), _b(multiPlain));
      expect(unzlib(multiZlib), _b(multiPlain));
    });

    test('long matches and large output', () {
      final out = gunzip(zerosGzip);
      expect(out.length, 200000);
      expect(out, _b(zerosPlain));
      expect(unzlib(zerosZlib), _b(zerosPlain));
    });

    test('gzip header with FEXTRA, FNAME, FCOMMENT and FHCRC', () {
      expect(gunzip(gzipAllHeaderFields), _b(fixedPlain));
    });

    test('empty plaintext', () {
      expect(gunzip(emptyGzip), isEmpty);
      expect(unzlib(emptyZlib), isEmpty);
    });

    test('gzip trailer CRC-32 with the top bit set', () {
      // gzip of "a": trailer CRC-32 is 0xE8B7BE43. Guards the trailer compare
      // against a signed CRC on dart2js (run with `dart test -p chrome`).
      expect(gunzip('H4sIAAAAAAAC/0sEAEO+t+gBAAAA'), ascii.encode('a'));
    });
  });

  group('CompressionType.none', () {
    test('returns the same bytes', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(identical(inflate.decode(bytes, CompressionType.none), bytes),
          isTrue);
    });
  });

  group('javascript-commons dataMocks.ts vectors', () {
    test('key list', () {
      // 64-bit hashes are not representable as web ints, so compare as text.
      expect(
          utf8.decode(gunzip(jsKeyListGzip)),
          '{"a":[1573573083296714675,8482869187405483569],'
          '"r":[8031872927333060586,6829471020522910836]}');
      expect(gunzip(jsKeyListGzip), _b(jsKeyListJson));
    });

    test('bitmaps (gzip and zlib)', () {
      expect(gunzip(jsBitmap0Gzip), _b(jsBitmap0Plain));
      expect(unzlib(jsBitmap1Zlib), _b(jsBitmap1Plain));
      expect(unzlib(jsBitmap2Zlib), _b(jsBitmap2Plain));
      expect(_b(jsBitmap0Plain).length, 128);
      expect(_b(jsBitmap1Plain).length, 4096);
    });

    test('split notifications (gzip, zlib)', () {
      final cases = <(Uint8List, int, int, String)>[
        (
          gunzip(jsSplit0C1),
          jsSplit0Length,
          jsSplit0ChangeNumber,
          jsSplit0Name
        ),
        (
          unzlib(jsSplit1C2),
          jsSplit1Length,
          jsSplit1ChangeNumber,
          jsSplit1Name
        ),
        (
          unzlib(jsSplit2C2),
          jsSplit2Length,
          jsSplit2ChangeNumber,
          jsSplit2Name
        ),
      ];
      for (final (out, length, changeNumber, name) in cases) {
        expect(out.length, length);
        final json = jsonDecode(utf8.decode(out)) as Map<String, dynamic>;
        expect(json['changeNumber'], changeNumber);
        expect(json['name'], name);
      }
      expect(jsSplit0ChangeNumber, 1684333081259);
    });
  });

  group('go-split-commons vectors (spec Appendix A.2)', () {
    test('FF_DEFINITION_GZIP', () {
      final out = gunzip(goFfDefinitionGzip);
      expect(out.length, goFfDefinitionGzipLength);
      final json = jsonDecode(utf8.decode(out)) as Map<String, dynamic>;
      expect(json['changeNumber'], 1684333081259);
    });

    test('FF_DEFINITION_ZLIB', () {
      final out = unzlib(goFfDefinitionZlib);
      expect(out.length, goFfDefinitionZlibLength);
      final json = jsonDecode(utf8.decode(out)) as Map<String, dynamic>;
      expect(json['changeNumber'], 1684265694505);
    });
  });

  group('errors', () {
    Uint8List mutated(String d, int index, int xor) =>
        _b(d)..[index < 0 ? _b(d).length + index : index] ^= xor;

    test('empty input', () {
      expect(() => inflate.decode(Uint8List(0), CompressionType.gzip),
          _throwsDecompression);
      expect(() => inflate.decode(Uint8List(0), CompressionType.zlib),
          _throwsDecompression);
    });

    test('gzip: bad magic, bad method, reserved flags', () {
      for (final (i, x) in [(0, 1), (1, 1), (2, 1), (3, 0x20)]) {
        expect(
            () => inflate.decode(
                mutated(dynamicGzip, i, x), CompressionType.gzip),
            _throwsDecompression,
            reason: 'byte $i');
      }
    });

    test('gzip: bad CRC-32 and bad ISIZE', () {
      for (var i = 1; i <= 8; i++) {
        expect(
            () => inflate.decode(
                mutated(dynamicGzip, -i, 1), CompressionType.gzip),
            _throwsDecompression,
            reason: 'trailer byte -$i');
      }
    });

    test('gzip: corrupt body is rejected', () {
      expect(
          () => inflate.decode(
              mutated(dynamicGzip, 40, 0xFF), CompressionType.gzip),
          _throwsDecompression);
    });

    test('gzip: trailing bytes after the trailer', () {
      final d = BytesBuilder()
        ..add(_b(fixedGzip))
        ..addByte(0);
      expect(() => inflate.decode(d.toBytes(), CompressionType.gzip),
          _throwsDecompression);
    });

    test('zlib: bad CM, bad CINFO, bad FCHECK, FDICT', () {
      final bad = <List<int>>[
        [0x79, 0x9c], // CM = 9
        [0x88, 0x1d], // CINFO = 8 (valid FCHECK)
        [0x78, 0x9d], // FCHECK mismatch
        [0x78, 0xbb], // FDICT set (valid FCHECK)
      ];
      for (final h in bad) {
        final d = _b(fixedZlib)..setRange(0, 2, h);
        expect(
            () => inflate.decode(d, CompressionType.zlib), _throwsDecompression,
            reason: '$h');
      }
    });

    test('zlib: bad Adler-32', () {
      for (var i = 1; i <= 4; i++) {
        expect(
            () => inflate.decode(
                mutated(dynamicZlib, -i, 1), CompressionType.zlib),
            _throwsDecompression);
      }
    });

    test('truncated input at every offset', () {
      for (final (d, type) in [
        (fixedGzip, CompressionType.gzip),
        (dynamicGzip, CompressionType.gzip),
        (storedZlib, CompressionType.zlib),
        (multiZlib, CompressionType.zlib),
        (gzipAllHeaderFields, CompressionType.gzip),
      ]) {
        final full = _b(d);
        for (var n = 0; n < full.length; n++) {
          expect(() => inflate.decode(Uint8List.sublistView(full, 0, n), type),
              _throwsDecompression,
              reason: 'cut at $n of ${full.length}');
        }
      }
    });

    test('output limit exceeded', () {
      const small = InflateDecompressor(maxOutputBytes: 1000);
      expect(() => small.decode(_b(zerosGzip), CompressionType.gzip),
          _throwsDecompression);
      expect(() => small.decode(_b(storedZlib), CompressionType.zlib),
          returnsNormally);
      const tiny = InflateDecompressor(maxOutputBytes: 10);
      expect(() => tiny.decode(_b(storedZlib), CompressionType.zlib),
          _throwsDecompression);
      expect(() => tiny.decode(_b(dynamicGzip), CompressionType.gzip),
          _throwsDecompression);
    });

    test('output exactly at the limit is accepted', () {
      const exact = InflateDecompressor(maxOutputBytes: 200000);
      expect(exact.decode(_b(zerosGzip), CompressionType.gzip).length, 200000);
      const below = InflateDecompressor(maxOutputBytes: 199999);
      expect(() => below.decode(_b(zerosZlib), CompressionType.zlib),
          _throwsDecompression);
    });

    test('default limit is 16 MiB', () {
      expect(const InflateDecompressor().maxOutputBytes, 16 * 1024 * 1024);
    });

    test('malformed DEFLATE streams', () {
      for (final d in [
        blockType3Zlib,
        farDistanceZlib,
        badLengthSymbolZlib,
        storedBadNlenZlib,
        oversubscribedZlib,
        incompleteDistInvalidZlib,
      ]) {
        expect(() => unzlib(d), _throwsDecompression, reason: d);
      }
    });

    test('spec Appendix A.3 malformed BOUNDED payload', () {
      expect(() => gunzip(malformedBounded), _throwsDecompression);
    });
  });
}
