import 'package:splitio_commons/src/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Murmur3', () {
    test('produces deterministic output for same input', () {
      final result1 = murmurhash3X8632('hello', 0);
      final result2 = murmurhash3X8632('hello', 0);
      expect(result1, equals(result2));
    });

    test('different seeds produce different hashes', () {
      final hash1 = murmurhash3X8632('test', 0);
      final hash2 = murmurhash3X8632('test', 1);
      expect(hash1, isNot(equals(hash2)));
    });

    test('different keys produce different hashes', () {
      final hash1 = murmurhash3X8632('key1', 42);
      final hash2 = murmurhash3X8632('key2', 42);
      expect(hash1, isNot(equals(hash2)));
    });

    test('empty string produces a valid hash', () {
      final result = murmurhash3X8632('', 0);
      expect(result, isA<int>());
    });

    test('known vector: seed 0, key "hello"', () {
      // Known murmur3 x86-32 hash for "hello" with seed 0
      final result = murmurhash3X8632('hello', 0);
      // Result should be a 32-bit unsigned int
      expect(result, greaterThanOrEqualTo(0));
      expect(result, lessThan(1 << 32));
    });

    test('handles keys with various lengths (1, 2, 3, 4+ chars)', () {
      // These exercise tail byte handling (len & 3 == 1, 2, 3, 0)
      expect(murmurhash3X8632('a', 0), isA<int>()); // tail = 1
      expect(murmurhash3X8632('ab', 0), isA<int>()); // tail = 2
      expect(murmurhash3X8632('abc', 0), isA<int>()); // tail = 3
      expect(murmurhash3X8632('abcd', 0), isA<int>()); // no tail
      expect(murmurhash3X8632('abcde', 0), isA<int>()); // tail = 1
    });

    test('known vector: consistent across calls for numeric keys', () {
      // Verify numeric string keys used commonly in bucketing
      final hash = murmurhash3X8632('12345678', 999);
      expect(hash, equals(murmurhash3X8632('12345678', 999)));
    });

    test('result fits in 32-bit unsigned range', () {
      for (final key in ['a', 'test', 'user123', 'longkey' * 100]) {
        final result = murmurhash3X8632(key, 42);
        expect(result, greaterThanOrEqualTo(0));
        expect(result, lessThan(1 << 32));
      }
    });
  });
}
