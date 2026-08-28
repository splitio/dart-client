import 'package:splitio_commons/src/auth/auth.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

void main() {
  group('StaticKeyAuthProvider', () {
    final target = Target(key: Key(matchingKey: 'user-1'));

    test('credential() returns the Bearer header passed to the constructor',
        () async {
      final provider = StaticKeyAuthProvider('Bearer my-sdk-key-123');
      final credential = await provider.credential(null);
      expect(credential.authHeader, equals('Bearer my-sdk-key-123'));
    });

    test('credential() ignores the target and returns the same header',
        () async {
      final provider = StaticKeyAuthProvider('Bearer key');
      final withTarget = await provider.credential(target);
      final withoutTarget = await provider.credential(null);
      expect(withTarget.authHeader, equals('Bearer key'));
      expect(withoutTarget.authHeader, equals('Bearer key'));
    });

    test('works with an empty header', () async {
      final provider = StaticKeyAuthProvider('');
      final credential = await provider.credential(null);
      expect(credential.authHeader, equals(''));
    });

    test('works with a base64-encoded key format', () async {
      final header = 'Bearer aWFtYXNka2tleQ==';
      final provider = StaticKeyAuthProvider(header);
      final credential = await provider.credential(null);
      expect(credential.authHeader, equals(header));
    });

    test('works with a key containing special characters', () async {
      final header = 'Bearer sdk-key/with+special=chars';
      final provider = StaticKeyAuthProvider(header);
      final credential = await provider.credential(null);
      expect(credential.authHeader, equals(header));
    });

    test('returns the same value on repeated calls', () async {
      final provider = StaticKeyAuthProvider('Bearer stable-key');
      expect((await provider.credential(null)).authHeader,
          equals('Bearer stable-key'));
      expect((await provider.credential(null)).authHeader,
          equals('Bearer stable-key'));
      expect((await provider.credential(null)).authHeader,
          equals('Bearer stable-key'));
    });

    test('invalidate() is a no-op and does not change subsequent credential()',
        () async {
      final provider = StaticKeyAuthProvider('Bearer key');
      expect(() => provider.invalidate(null), returnsNormally);
      expect(() => provider.invalidate(target), returnsNormally);
      final credential = await provider.credential(null);
      expect(credential.authHeader, equals('Bearer key'));
    });

    test('clearAll() is a no-op and does not change subsequent credential()',
        () async {
      final provider = StaticKeyAuthProvider('Bearer key');
      expect(() => provider.clearAll(), returnsNormally);
      final credential = await provider.credential(null);
      expect(credential.authHeader, equals('Bearer key'));
    });

    test('implements AuthProvider interface', () async {
      final AuthProvider provider = StaticKeyAuthProvider('Bearer key');
      expect(
          (await provider.credential(null)).authHeader, equals('Bearer key'));
    });
  });
}
