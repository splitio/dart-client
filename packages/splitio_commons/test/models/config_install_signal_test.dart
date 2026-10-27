import 'package:splitio_commons/src/models/config.dart';
import 'package:test/test.dart';

void main() {
  group('SplitClientConfig.installSignalHandler', () {
    test('defaults to true', () {
      const cfg = SplitClientConfig();
      expect(cfg.installSignalHandler, isTrue);
    });

    test('can be set to false', () {
      const cfg = SplitClientConfig(installSignalHandler: false);
      expect(cfg.installSignalHandler, isFalse);
    });
  });
}
