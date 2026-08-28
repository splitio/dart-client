import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('AllKeysMatcher', () {
    test('always returns true', () {
      const matcher = AllKeysMatcher();
      expect(matcher.match('anything', defaultCtx()), isTrue);
      expect(matcher.match(null, defaultCtx()), isTrue);
      expect(matcher.match(42, defaultCtx()), isTrue);
      expect(matcher.match(<String>[], defaultCtx()), isTrue);
      expect(matcher.match(<String, dynamic>{}, defaultCtx()), isTrue);
    });
  });
}
