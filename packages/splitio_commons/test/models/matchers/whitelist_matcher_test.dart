import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('WhitelistMatcher', () {
    const matcher = WhitelistMatcher(whitelist: {'user1', 'user2'});

    test('matches value in whitelist', () {
      expect(matcher.match('user1', defaultCtx()), isTrue);
      expect(matcher.match('user2', defaultCtx()), isTrue);
    });

    test('does not match value not in whitelist', () {
      expect(matcher.match('user3', defaultCtx()), isFalse);
      expect(matcher.match('', defaultCtx()), isFalse);
    });

    test('returns false for non-String value', () {
      expect(matcher.match(123, defaultCtx()), isFalse);
      expect(matcher.match(null, defaultCtx()), isFalse);
      expect(matcher.match(true, defaultCtx()), isFalse);
      expect(matcher.match(<String>[], defaultCtx()), isFalse);
    });

    test('empty whitelist matches nothing', () {
      const emptyMatcher = WhitelistMatcher(whitelist: {});
      expect(emptyMatcher.match('user1', defaultCtx()), isFalse);
      expect(emptyMatcher.match('', defaultCtx()), isFalse);
    });
  });
}
