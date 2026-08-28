import 'package:splitio_client_side/src/internal/user_consent.dart';
import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

void main() {
  group('UserConsentManager', () {
    test('defaults to granted', () {
      final manager = UserConsentManager();
      expect(manager.status, ConsentStatus.granted);
    });

    test('setStatus updates status', () {
      final manager = UserConsentManager();
      manager.setStatus(ConsentStatus.declined);
      expect(manager.status, ConsentStatus.declined);
    });

    test('fires onDeclined callback on GRANTED->DECLINED transition', () {
      final manager = UserConsentManager();
      var fired = 0;
      manager.setOnDeclined(() => fired++);

      manager.setStatus(ConsentStatus.declined);

      expect(fired, 1);
    });

    test('does not fire onDeclined when already declined', () {
      final manager = UserConsentManager(initialStatus: ConsentStatus.declined);
      var fired = 0;
      manager.setOnDeclined(() => fired++);

      manager.setStatus(ConsentStatus.declined);

      expect(fired, 0);
    });

    test('does not fire onDeclined transitioning to granted or unknown', () {
      final manager = UserConsentManager();
      var fired = 0;
      manager.setOnDeclined(() => fired++);

      manager.setStatus(ConsentStatus.unknown);
      manager.setStatus(ConsentStatus.granted);

      expect(fired, 0);
    });

    test('fires again on a second GRANTED->DECLINED transition', () {
      final manager = UserConsentManager();
      var fired = 0;
      manager.setOnDeclined(() => fired++);

      manager.setStatus(ConsentStatus.declined);
      manager.setStatus(ConsentStatus.granted);
      manager.setStatus(ConsentStatus.declined);

      expect(fired, 2);
    });
  });
}
