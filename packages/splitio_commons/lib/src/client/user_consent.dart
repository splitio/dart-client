import 'package:splitio_commons/src/models/enums.dart';

class UserConsentManager {
  ConsentStatus _status;
  void Function()? _onDeclined;

  UserConsentManager({ConsentStatus initialStatus = ConsentStatus.granted})
      : _status = initialStatus;

  ConsentStatus get status => _status;

  /// Registers a callback invoked whenever consent transitions to
  /// [ConsentStatus.declined], so queued recorder data can be dropped (§7.2).
  void setOnDeclined(void Function() callback) {
    _onDeclined = callback;
  }

  void setStatus(ConsentStatus status) {
    final wasDeclined = _status == ConsentStatus.declined;
    _status = status;
    if (status == ConsentStatus.declined && !wasDeclined) {
      _onDeclined?.call();
    }
  }
}
