import 'package:splitio_client_side/src/internal/split_manager.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/storage/rule_store.dart';
import 'package:test/test.dart';

void main() {
  group('SplitManagerImpl.split', () {
    late InMemoryRuleStore store;
    late SplitLogger log;
    late SplitManagerImpl manager;

    setUp(() {
      store = InMemoryRuleStore();
      log = SplitLogger(level: LogLevel.none);
      manager = SplitManagerImpl(ruleStore: store, logger: log);
    });

    test('returns null on empty flag name', () {
      expect(manager.split(''), isNull);
    });

    test('returns null on whitespace-only flag name', () {
      expect(manager.split('   '), isNull);
    });

    test('trims and looks up trimmed name (null when not in store)', () {
      expect(manager.split('  my_flag  '), isNull);
    });
  });
}
