import 'package:splitio_commons/src/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Semver', () {
    group('build (parsing)', () {
      test('parses simple version', () {
        final v = Semver.build('1.2.3');
        expect(v, isNotNull);
        expect(v!.major, equals(1));
        expect(v.minor, equals(2));
        expect(v.patch, equals(3));
        expect(v.prerelease, isEmpty);
        expect(v.metadata, isNull);
      });

      test('parses version with prerelease', () {
        final v = Semver.build('1.0.0-alpha.1');
        expect(v, isNotNull);
        expect(v!.prerelease, equals(['alpha', '1']));
      });

      test('parses version with metadata', () {
        final v = Semver.build('1.0.0+build.123');
        expect(v, isNotNull);
        expect(v!.metadata, equals('build.123'));
      });

      test('parses version with prerelease and metadata', () {
        final v = Semver.build('1.0.0-beta.2+build.456');
        expect(v, isNotNull);
        expect(v!.prerelease, equals(['beta', '2']));
        expect(v.metadata, equals('build.456'));
      });

      test('trims whitespace', () {
        final v = Semver.build('  2.0.0  ');
        expect(v, isNotNull);
        expect(v!.major, equals(2));
      });

      test('returns null for empty string', () {
        expect(Semver.build(''), isNull);
        expect(Semver.build('   '), isNull);
      });

      test('returns null for incomplete version', () {
        expect(Semver.build('1.2'), isNull);
        expect(Semver.build('1'), isNull);
      });

      test('returns null for non-numeric parts', () {
        expect(Semver.build('a.b.c'), isNull);
        expect(Semver.build('1.x.3'), isNull);
      });

      test('returns null for negative numbers', () {
        expect(Semver.build('-1.0.0'), isNull);
      });

      test('returns null for empty prerelease identifier', () {
        expect(Semver.build('1.0.0-'), isNull);
        expect(Semver.build('1.0.0-alpha.'), isNull);
      });

      test('returns null for too many version parts', () {
        expect(Semver.build('1.2.3.4'), isNull);
      });
    });

    group('version() normalization', () {
      test('basic version round-trips', () {
        expect(Semver.build('1.2.3')!.version(), equals('1.2.3'));
      });

      test('includes prerelease', () {
        expect(Semver.build('1.0.0-alpha')!.version(), equals('1.0.0-alpha'));
      });

      test('includes metadata', () {
        expect(
          Semver.build('1.0.0+build')!.version(),
          equals('1.0.0+build'),
        );
      });

      test('full version round-trips', () {
        expect(
          Semver.build('2.1.0-rc.1+20230101')!.version(),
          equals('2.1.0-rc.1+20230101'),
        );
      });
    });

    group('comparePrecedence', () {
      test('higher major is greater', () {
        final a = Semver.build('2.0.0')!;
        final b = Semver.build('1.9.9')!;
        expect(a.comparePrecedence(b), greaterThan(0));
      });

      test('higher minor is greater', () {
        final a = Semver.build('1.2.0')!;
        final b = Semver.build('1.1.9')!;
        expect(a.comparePrecedence(b), greaterThan(0));
      });

      test('higher patch is greater', () {
        final a = Semver.build('1.0.2')!;
        final b = Semver.build('1.0.1')!;
        expect(a.comparePrecedence(b), greaterThan(0));
      });

      test('same version is equal', () {
        final a = Semver.build('1.0.0')!;
        final b = Semver.build('1.0.0')!;
        expect(a.comparePrecedence(b), equals(0));
      });

      test('stable > prerelease (same version)', () {
        final stable = Semver.build('1.0.0')!;
        final pre = Semver.build('1.0.0-alpha')!;
        expect(stable.comparePrecedence(pre), greaterThan(0));
        expect(pre.comparePrecedence(stable), lessThan(0));
      });

      test('numeric prerelease identifiers compared numerically', () {
        final a = Semver.build('1.0.0-2')!;
        final b = Semver.build('1.0.0-10')!;
        // 2 < 10 numerically
        expect(a.comparePrecedence(b), lessThan(0));
      });

      test('string prerelease identifiers compared lexically', () {
        final a = Semver.build('1.0.0-alpha')!;
        final b = Semver.build('1.0.0-beta')!;
        expect(a.comparePrecedence(b), lessThan(0));
      });

      test('numeric identifier < string identifier', () {
        final a = Semver.build('1.0.0-1')!;
        final b = Semver.build('1.0.0-alpha')!;
        expect(a.comparePrecedence(b), lessThan(0));
      });

      test('more prerelease identifiers is greater when prefix matches', () {
        final a = Semver.build('1.0.0-alpha.1')!;
        final b = Semver.build('1.0.0-alpha')!;
        expect(a.comparePrecedence(b), greaterThan(0));
      });

      test('metadata is ignored in comparison', () {
        final a = Semver.build('1.0.0+build1')!;
        final b = Semver.build('1.0.0+build2')!;
        expect(a.comparePrecedence(b), equals(0));
      });
    });
  });
}
