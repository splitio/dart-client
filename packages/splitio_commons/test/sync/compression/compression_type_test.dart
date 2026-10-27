import 'package:splitio_commons/src/sync/compression/compression_type.dart';
import 'package:test/test.dart';

void main() {
  group('CompressionType.fromWire', () {
    test('maps 0, 1, 2', () {
      expect(CompressionType.fromWire(0), CompressionType.none);
      expect(CompressionType.fromWire(1), CompressionType.gzip);
      expect(CompressionType.fromWire(2), CompressionType.zlib);
    });

    test('returns null for anything else', () {
      for (final c in <Object?>[3, -1, 99, '1', 1.5, null, true, <int>[]]) {
        expect(CompressionType.fromWire(c), isNull, reason: '$c');
      }
    });
  });
}
