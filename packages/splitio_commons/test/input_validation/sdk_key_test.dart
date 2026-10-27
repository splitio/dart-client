import 'package:splitio_commons/src/input_validation/sdk_key.dart';
import 'package:test/test.dart';

void main() {
  group('validateSdkKey', () {
    test('accepts a non-empty sdkKey', () {
      final r = validateSdkKey('abcd1234', 'SplitFactory.create');
      expect(r.isValid, isTrue);
      expect(r.value, 'abcd1234');
    });

    test('rejects an empty sdkKey', () {
      final r = validateSdkKey('', 'SplitFactory.create');
      expect(r.isValid, isFalse);
      expect(r.error, contains('SplitFactory.create'));
    });

    test('rejects a whitespace-only sdkKey', () {
      final r = validateSdkKey('   ', 'SplitFactory.create');
      expect(r.isValid, isFalse);
      expect(r.error, contains('empty SDK key'));
    });
  });
}
