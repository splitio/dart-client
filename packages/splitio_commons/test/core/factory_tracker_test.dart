import 'dart:async';

import 'package:splitio_commons/src/core/factory_tracker.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:test/test.dart';

void main() {
  late List<String> logs;
  final log = SplitLogger(level: LogLevel.warning);

  void run(void Function() body) => runZoned(body,
      zoneSpecification:
          ZoneSpecification(print: (_, __, ___, l) => logs.add(l)));

  setUp(() {
    logs = [];
    FactoryTracker.resetForTesting();
  });

  test('first factory does not warn', () {
    run(() => FactoryTracker.track('k1', log));
    expect(logs, isEmpty);
    expect(FactoryTracker.liveCount('k1'), 1);
  });

  test('second factory with the same key warns with the live count', () {
    run(() {
      FactoryTracker.track('k1', log);
      FactoryTracker.track('k1', log);
      FactoryTracker.track('k1', log);
    });
    expect(logs, hasLength(2));
    expect(
        logs[0], contains('You already have 1 factory/ies with this SDK Key.'));
    expect(
        logs[1], contains('You already have 2 factory/ies with this SDK Key.'));
    expect(logs[0], contains('Singleton pattern'));
    expect(logs[0], contains('settings: You already have'));
  });

  test('a factory for a different key warns that another instance exists', () {
    run(() {
      FactoryTracker.track('k1', log);
      FactoryTracker.track('k2', log);
    });
    expect(logs, hasLength(1));
    expect(logs.single,
        contains('You already have an instance of the Split factory.'));
  });

  test('release decrements and removes the key at zero', () {
    run(() {
      FactoryTracker.track('k1', log);
      FactoryTracker.track('k1', log);
    });
    FactoryTracker.release('k1');
    expect(FactoryTracker.liveCount('k1'), 1);
    FactoryTracker.release('k1');
    expect(FactoryTracker.liveCount('k1'), 0);
    logs.clear();
    run(() => FactoryTracker.track('k2', log));
    expect(logs, isEmpty, reason: 'released keys no longer count');
  });

  test('release of an unknown key is a no-op', () {
    FactoryTracker.release('nope');
    expect(FactoryTracker.liveCount('nope'), 0);
  });
}
