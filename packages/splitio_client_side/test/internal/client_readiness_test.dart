import 'package:splitio_client_side/src/internal/client_readiness.dart';
import 'package:splitio_commons/src/events/events_manager.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:test/test.dart';

void main() {
  late ClientReadiness readiness;

  ClientReadiness build({int readyTimeout = 0}) => ClientReadiness(
        log: SplitLogger(level: LogLevel.none),
        readyTimeoutSeconds: readyTimeout,
      );

  setUp(() => readiness = build());
  tearDown(() => readiness.dispose());

  group('READY', () {
    test('requires rules and the client\'s own memberships', () {
      final a = EventsManager();
      final b = EventsManager();
      readiness.register('a', a);
      readiness.register('b', b);

      readiness.onMembershipsResult('a', true);
      expect(a.isReady, isFalse, reason: 'rules not synced yet');

      readiness.onRulesResult(true);
      expect(a.isReady, isTrue);
      expect(b.isReady, isFalse,
          reason: 'b MUST NOT become READY on a\'s memberships');

      readiness.onMembershipsResult('b', true);
      expect(b.isReady, isTrue);
    });

    test('failed results never make a client ready', () {
      final a = EventsManager();
      readiness.register('a', a);
      readiness.onRulesResult(false);
      readiness.onMembershipsResult('a', false);
      expect(a.isReady, isFalse);
      readiness.onRulesResult(true);
      readiness.onMembershipsResult('a', true);
      expect(a.isReady, isTrue);
    });

    test('a client registered after global sync awaits only its memberships',
        () {
      readiness.onRulesResult(true);
      readiness.onMembershipsResult('a', true);

      final late = EventsManager();
      readiness.register('late', late);
      expect(late.isReady, isFalse);

      readiness.onMembershipsResult('late', true);
      expect(late.isReady, isTrue);
    });

    test('a client whose memberships already synced is ready on register', () {
      readiness.onRulesResult(true);
      readiness.onMembershipsResult('a', true);
      final same = EventsManager();
      readiness.register('a', same);
      expect(same.isReady, isTrue);
    });
  });

  group('UPDATE', () {
    test('nothing is emitted before READY', () async {
      final a = EventsManager();
      readiness.register('a', a);
      final updates = <List<String>>[];
      a.onUpdated.listen(updates.add);

      readiness.onFlagsChanged(['f']);
      readiness.onMembershipsChanged('a');
      await Future<void>.delayed(Duration.zero);
      expect(updates, isEmpty);
    });

    test('memberships change reaches only clients of that matching key',
        () async {
      final a1 = EventsManager();
      final a2 = EventsManager(); // same matching key, other bucketing key
      final b = EventsManager();
      readiness.register('a', a1);
      readiness.register('a', a2);
      readiness.register('b', b);
      readiness.onRulesResult(true);
      readiness.onMembershipsResult('a', true);
      readiness.onMembershipsResult('b', true);

      final a1Updates = <List<String>>[];
      final a2Updates = <List<String>>[];
      final bUpdates = <List<String>>[];
      a1.onUpdated.listen(a1Updates.add);
      a2.onUpdated.listen(a2Updates.add);
      b.onUpdated.listen(bUpdates.add);

      readiness.onMembershipsChanged('a');
      await Future<void>.delayed(Duration.zero);

      expect(a1Updates, [[]]);
      expect(a2Updates, [[]]);
      expect(bUpdates, isEmpty);
    });

    test('flag change reaches every ready client', () async {
      final a = EventsManager();
      final b = EventsManager();
      readiness.register('a', a);
      readiness.register('b', b);
      readiness.onRulesResult(true);
      readiness.onMembershipsResult('a', true);
      readiness.onMembershipsResult('b', true);
      final aUpdates = <List<String>>[];
      final bUpdates = <List<String>>[];
      a.onUpdated.listen(aUpdates.add);
      b.onUpdated.listen(bUpdates.add);

      readiness.onFlagsChanged(['f']);
      await Future<void>.delayed(Duration.zero);

      expect(aUpdates, [
        ['f']
      ]);
      expect(bUpdates, [
        ['f']
      ]);
    });
  });

  group('unregister and dispose', () {
    test('unregister closes only that client\'s stream and keeps others',
        () async {
      final a = EventsManager();
      final b = EventsManager();
      readiness.register('a', a);
      readiness.register('b', b);
      readiness.onRulesResult(true);
      readiness.onMembershipsResult('a', true);
      readiness.onMembershipsResult('b', true);

      var aDone = false;
      final bUpdates = <List<String>>[];
      a.onUpdated.listen(null, onDone: () => aDone = true);
      b.onUpdated.listen(bUpdates.add);

      await readiness.unregister(a);
      readiness.onFlagsChanged(['f']);
      await Future<void>.delayed(Duration.zero);

      expect(aDone, isTrue);
      expect(bUpdates, [
        ['f']
      ]);
    });

    test('dispose disposes every client and ignores later registrations',
        () async {
      final a = EventsManager();
      readiness.register('a', a);
      await readiness.dispose();
      expect(a.isDestroyed, isTrue);

      final after = EventsManager();
      readiness.register('b', after);
      readiness.onRulesResult(true);
      readiness.onMembershipsResult('b', true);
      expect(after.isReady, isFalse);
    });
  });

  group('TIMEOUT', () {
    test('fires per client after readyTimeout and READY may still follow',
        () async {
      readiness = build(readyTimeout: 1);
      final a = EventsManager();
      final b = EventsManager();
      readiness.register('a', a);
      readiness.register('b', b);
      readiness.onRulesResult(true);
      readiness.onMembershipsResult('a', true);

      await b.onTimeout.timeout(const Duration(seconds: 3));
      expect(a.isReady, isTrue);
      expect(b.isReady, isFalse);

      readiness.onMembershipsResult('b', true);
      expect(b.isReady, isTrue);
    });
  });
}
