import 'package:splitio_commons/src/input_validation/operational.dart';
import 'package:test/test.dart';

void main() {
  group('validateIfNotDestroyed', () {
    test('passes when not destroyed', () {
      final r =
          validateIfNotDestroyed(isDestroyed: false, method: 'getTreatment');
      expect(r.isValid, isTrue);
    });
    test('fails when destroyed', () {
      final r =
          validateIfNotDestroyed(isDestroyed: true, method: 'getTreatment');
      expect(r.isValid, isFalse);
      expect(r.error, contains('destroyed'));
    });
  });

  group('validateIfReady', () {
    test('passes when ready', () {
      final r = validateIfReady(isReady: true, method: 'getTreatment');
      expect(r.isValid, isTrue);
    });
    test('warns when not ready', () {
      final r = validateIfReady(isReady: false, method: 'getTreatment');
      expect(r.isValid, isFalse);
      expect(r.error, contains('not ready'));
    });
  });
}
