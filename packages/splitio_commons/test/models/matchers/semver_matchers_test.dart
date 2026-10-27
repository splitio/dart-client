import 'dart:async';

import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart' hide Matcher;

import 'test_helpers.dart';

void main() {
  group('EqualToSemverMatcher', () {
    const matcher = EqualToSemverMatcher(version: '1.2.3');

    test('matches equal version', () {
      expect(matcher.match('1.2.3', defaultCtx()), isTrue);
    });

    test('does not match versions with different metadata or prerelease', () {
      // version() includes metadata and prerelease in the comparison
      expect(matcher.match('1.2.3+build', defaultCtx()), isFalse);
      expect(matcher.match('1.2.3-alpha', defaultCtx()), isFalse);
    });

    test('does not match different versions', () {
      expect(matcher.match('1.2.4', defaultCtx()), isFalse);
      expect(matcher.match('1.3.3', defaultCtx()), isFalse);
      expect(matcher.match('2.2.3', defaultCtx()), isFalse);
      expect(matcher.match('1.2.2', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
      expect(matcher.match(true, defaultCtx()), isFalse);
    });

    test('returns false for invalid semver', () {
      expect(matcher.match('invalid', defaultCtx()), isFalse);
      expect(matcher.match('1.2', defaultCtx()), isFalse);
      expect(matcher.match('', defaultCtx()), isFalse);
    });
  });

  group('GreaterThanOrEqualToSemverMatcher', () {
    const matcher = GreaterThanOrEqualToSemverMatcher(version: '1.2.3');

    test('matches equal version', () {
      expect(matcher.match('1.2.3', defaultCtx()), isTrue);
    });

    test('matches greater versions', () {
      expect(matcher.match('1.2.4', defaultCtx()), isTrue);
      expect(matcher.match('1.3.0', defaultCtx()), isTrue);
      expect(matcher.match('2.0.0', defaultCtx()), isTrue);
    });

    test('does not match lesser versions', () {
      expect(matcher.match('1.2.2', defaultCtx()), isFalse);
      expect(matcher.match('1.1.9', defaultCtx()), isFalse);
      expect(matcher.match('0.9.9', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
    });

    test('returns false for invalid semver', () {
      expect(matcher.match('invalid', defaultCtx()), isFalse);
    });
  });

  group('LessThanOrEqualToSemverMatcher', () {
    const matcher = LessThanOrEqualToSemverMatcher(version: '1.2.3');

    test('matches equal version', () {
      expect(matcher.match('1.2.3', defaultCtx()), isTrue);
    });

    test('matches lesser versions', () {
      expect(matcher.match('1.2.2', defaultCtx()), isTrue);
      expect(matcher.match('1.1.9', defaultCtx()), isTrue);
      expect(matcher.match('0.9.9', defaultCtx()), isTrue);
    });

    test('does not match greater versions', () {
      expect(matcher.match('1.2.4', defaultCtx()), isFalse);
      expect(matcher.match('1.3.0', defaultCtx()), isFalse);
      expect(matcher.match('2.0.0', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
    });

    test('returns false for invalid semver', () {
      expect(matcher.match('invalid', defaultCtx()), isFalse);
    });
  });

  group('BetweenSemverMatcher', () {
    const matcher = BetweenSemverMatcher(start: '1.2.0', end: '1.5.0');

    test('matches version at start boundary', () {
      expect(matcher.match('1.2.0', defaultCtx()), isTrue);
    });

    test('matches version at end boundary', () {
      expect(matcher.match('1.5.0', defaultCtx()), isTrue);
    });

    test('matches version in range', () {
      expect(matcher.match('1.3.0', defaultCtx()), isTrue);
      expect(matcher.match('1.4.5', defaultCtx()), isTrue);
    });

    test('does not match version below start', () {
      expect(matcher.match('1.1.9', defaultCtx()), isFalse);
      expect(matcher.match('0.9.0', defaultCtx()), isFalse);
    });

    test('does not match version above end', () {
      expect(matcher.match('1.5.1', defaultCtx()), isFalse);
      expect(matcher.match('2.0.0', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
    });

    test('returns false for invalid semver', () {
      expect(matcher.match('invalid', defaultCtx()), isFalse);
    });
  });

  group('InListSemverMatcher', () {
    const matcher = InListSemverMatcher(versions: ['1.2.3', '1.5.0', '2.0.0']);

    test('matches version in list', () {
      expect(matcher.match('1.2.3', defaultCtx()), isTrue);
      expect(matcher.match('1.5.0', defaultCtx()), isTrue);
      expect(matcher.match('2.0.0', defaultCtx()), isTrue);
    });

    test('does not match version not in list', () {
      expect(matcher.match('1.2.4', defaultCtx()), isFalse);
      expect(matcher.match('1.4.0', defaultCtx()), isFalse);
      expect(matcher.match('3.0.0', defaultCtx()), isFalse);
    });

    test('returns false for non-String values', () {
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(123, defaultCtx()), isFalse);
    });

    test('returns false for invalid semver', () {
      expect(matcher.match('invalid', defaultCtx()), isFalse);
    });

    test('handles empty list', () {
      const emptyMatcher = InListSemverMatcher(versions: []);
      expect(emptyMatcher.match('1.2.3', defaultCtx()), isFalse);
    });

    test('compares normalized versions', () {
      // version() preserves metadata, so '1.2.3+build' != '1.2.3'
      expect(matcher.match('1.2.3+build', defaultCtx()), isFalse);
    });
  });

  group('unparsable attribute value', () {
    final matchers = <String, Matcher>{
      'EQUAL_TO_SEMVER': const EqualToSemverMatcher(version: '1.2.3'),
      'BETWEEN_SEMVER':
          const BetweenSemverMatcher(start: '1.0.0', end: '2.0.0'),
      'GREATER_THAN_OR_EQUAL_TO_SEMVER':
          const GreaterThanOrEqualToSemverMatcher(version: '1.0.0'),
      'LESS_THAN_OR_EQUAL_TO_SEMVER':
          const LessThanOrEqualToSemverMatcher(version: '1.0.0'),
      'IN_LIST_SEMVER': const InListSemverMatcher(versions: ['1.2.3']),
    };

    matchers.forEach((name, matcher) {
      test('$name does not match and logs an ERROR', () {
        final lines = <String>[];
        late bool result;
        runZoned(
          () => result = matcher.match('not-a-semver',
              defaultCtx(logger: SplitLogger(level: LogLevel.error))),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => lines.add(line),
          ),
        );
        expect(result, isFalse);
        expect(lines, hasLength(1));
        expect(lines.single, contains('[ERROR]'));
        expect(lines.single, contains(name));
        expect(lines.single, contains('not-a-semver'));
      });
    });

    test('a valid semver logs nothing', () {
      final lines = <String>[];
      runZoned(
        () => const EqualToSemverMatcher(version: '1.2.3').match(
            '1.2.3', defaultCtx(logger: SplitLogger(level: LogLevel.error))),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => lines.add(line),
        ),
      );
      expect(lines, isEmpty);
    });
  });
}
