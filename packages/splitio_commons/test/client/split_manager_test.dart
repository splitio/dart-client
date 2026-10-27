import 'dart:async';

import 'package:splitio_commons/src/client/split_manager.dart';
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

  group('SplitManagerImpl after factory destroy (spec §7.1)', () {
    late List<String> logs;
    late SplitManagerImpl manager;
    var destroyed = false;

    setUp(() {
      destroyed = false;
      logs = [];
      manager = SplitManagerImpl(
        ruleStore: InMemoryRuleStore(),
        logger: SplitLogger(level: LogLevel.error),
        isDestroyed: () => destroyed,
      );
    });

    void capture(void Function() body) {
      runZoned(body,
          zoneSpecification:
              ZoneSpecification(print: (_, __, ___, l) => logs.add(l)));
    }

    test('logs ERROR per method and returns null/empty once destroyed',
        () async {
      destroyed = true;
      capture(() {
        expect(manager.split('f'), isNull);
        expect(manager.splits(), isEmpty);
        expect(manager.names(), isEmpty);
      });
      for (final m in ['split', 'splits', 'names']) {
        expect(
            logs,
            contains(
                '[Split][ERROR] $m: Client has already been destroyed - no calls possible.'));
      }
    });

    test('does not log while the factory is alive', () {
      capture(() {
        manager.splits();
        manager.names();
      });
      expect(logs, isEmpty);
    });
  });
}
