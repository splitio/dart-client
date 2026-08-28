import 'package:splitio_commons/src/auth/auth.dart';
import 'package:test/test.dart';

void main() {
  group('Credential', () {
    test('carries the authHeader value', () {
      const c = Credential(authHeader: 'Bearer my-sdk-key');
      expect(c.authHeader, equals('Bearer my-sdk-key'));
    });

    test('equality is by authHeader', () {
      const a = Credential(authHeader: 'Bearer x');
      const b = Credential(authHeader: 'Bearer x');
      const c = Credential(authHeader: 'Bearer y');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('is not equal to a JwtCredential with the same header', () {
      const base = Credential(authHeader: 'Bearer tok');
      const jwt = JwtCredential(
        token: 'tok',
        channels: [],
        pushEnabled: true,
        expiresAt: 1,
        connDelaySeconds: 0,
      );
      expect(base, isNot(equals(jwt)));
    });
  });

  group('JwtCredential', () {
    JwtCredential build() => const JwtCredential(
          token: 'jwt-token',
          channels: ['channel_a', 'channel_b'],
          pushEnabled: true,
          expiresAt: 1752566400,
          connDelaySeconds: 5,
        );

    test('exposes all fields', () {
      final c = build();
      expect(c.token, equals('jwt-token'));
      expect(c.channels, equals(['channel_a', 'channel_b']));
      expect(c.pushEnabled, isTrue);
      expect(c.expiresAt, equals(1752566400));
      expect(c.connDelaySeconds, equals(5));
    });

    test('defaults authHeader to "Bearer <token>"', () {
      final c = build();
      expect(c.authHeader, equals('Bearer jwt-token'));
    });

    test('is a Credential', () {
      expect(build(), isA<Credential>());
    });

    test('honors an explicit authHeader override', () {
      const c = JwtCredential(
        token: 'tok',
        channels: [],
        pushEnabled: false,
        expiresAt: 0,
        connDelaySeconds: 0,
        authHeader: 'Custom header',
      );
      expect(c.authHeader, equals('Custom header'));
    });

    test('pushEnabled=false is representable (poll only)', () {
      const c = JwtCredential(
        token: '',
        channels: [],
        pushEnabled: false,
        expiresAt: 0,
        connDelaySeconds: 0,
      );
      expect(c.pushEnabled, isFalse);
      expect(c.token, isEmpty);
    });

    test('equality considers all fields including channels order', () {
      final a = build();
      final b = build();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      const different = JwtCredential(
        token: 'jwt-token',
        channels: ['channel_b', 'channel_a'],
        pushEnabled: true,
        expiresAt: 1752566400,
        connDelaySeconds: 5,
      );
      expect(a, isNot(equals(different)));
    });

    test('differs when any field differs', () {
      final base = build();
      expect(
        base,
        isNot(equals(const JwtCredential(
          token: 'other',
          channels: ['channel_a', 'channel_b'],
          pushEnabled: true,
          expiresAt: 1752566400,
          connDelaySeconds: 5,
        ))),
      );
      expect(
        base,
        isNot(equals(const JwtCredential(
          token: 'jwt-token',
          channels: ['channel_a', 'channel_b'],
          pushEnabled: false,
          expiresAt: 1752566400,
          connDelaySeconds: 5,
        ))),
      );
      expect(
        base,
        isNot(equals(const JwtCredential(
          token: 'jwt-token',
          channels: ['channel_a', 'channel_b'],
          pushEnabled: true,
          expiresAt: 999,
          connDelaySeconds: 5,
        ))),
      );
      expect(
        base,
        isNot(equals(const JwtCredential(
          token: 'jwt-token',
          channels: ['channel_a', 'channel_b'],
          pushEnabled: true,
          expiresAt: 1752566400,
          connDelaySeconds: 99,
        ))),
      );
    });
  });
}
