import 'dart:async';

import 'package:splitio_commons/src/events/events.dart';
import 'package:test/test.dart';

void main() {
  group('EventsManager — new whenX primitives', () {
    late EventsManager manager;

    setUp(() {
      manager = EventsManager();
    });

    tearDown(() async {
      await manager.dispose();
    });

    // --- onReady ---

    test('onReady completes when notifyReady is called', () async {
      final future = manager.onReady;
      manager.notifyReady();
      await expectLater(future, completes);
    });

    test('onReady is latched — subscribing after notifyReady returns a resolved future', () async {
      manager.notifyReady();
      // subscribe AFTER ready
      await expectLater(manager.onReady, completes);
    });

    test('notifyReady is idempotent — calling twice does not throw', () {
      manager.notifyReady();
      expect(() => manager.notifyReady(), returnsNormally);
    });

    test('isReady starts false and becomes true after notifyReady', () {
      expect(manager.isReady, isFalse);
      manager.notifyReady();
      expect(manager.isReady, isTrue);
    });

    // --- onTimeout ---

    test('onTimeout completes when notifyTimeout is called', () async {
      final future = manager.onTimeout;
      manager.notifyTimeout();
      await expectLater(future, completes);
    });

    test('onTimeout is latched — subscribing after notifyTimeout returns a resolved future', () async {
      manager.notifyTimeout();
      await expectLater(manager.onTimeout, completes);
    });

    test('notifyTimeout is idempotent — calling twice does not throw', () {
      manager.notifyTimeout();
      expect(() => manager.notifyTimeout(), returnsNormally);
    });

    test('onReady and onTimeout are independent — both can fire', () async {
      manager.notifyTimeout();
      manager.notifyReady();
      await expectLater(manager.onReady, completes);
      await expectLater(manager.onTimeout, completes);
    });

    // --- onUpdated ---

    test('onUpdated emits the changed flag names', () async {
      final received = <List<String>>[];
      final sub = manager.onUpdated.listen(received.add);

      manager.notifyUpdate(['flag_a', 'flag_b']);
      await Future.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received[0], equals(['flag_a', 'flag_b']));
      await sub.cancel();
    });

    test('onUpdated fires multiple times (not latched)', () async {
      final received = <List<String>>[];
      final sub = manager.onUpdated.listen(received.add);

      manager.notifyUpdate(['a']);
      manager.notifyUpdate(['b']);
      manager.notifyUpdate(['c']);
      await Future.delayed(Duration.zero);

      expect(received, hasLength(3));
      await sub.cancel();
    });

    test('onUpdated is broadcast — multiple subscribers each receive events', () async {
      final a = <List<String>>[];
      final b = <List<String>>[];
      final subA = manager.onUpdated.listen(a.add);
      final subB = manager.onUpdated.listen(b.add);

      manager.notifyUpdate(['flag_x']);
      await Future.delayed(Duration.zero);

      expect(a, hasLength(1));
      expect(b, hasLength(1));
      await subA.cancel();
      await subB.cancel();
    });

    test('onUpdated payload is unmodifiable', () async {
      List<String>? payload;
      final sub = manager.onUpdated.listen((p) => payload = p);
      manager.notifyUpdate(['flag_z']);
      await Future.delayed(Duration.zero);
      expect(() => payload!.add('extra'), throwsUnsupportedError);
      await sub.cancel();
    });

    // --- dispose ---

    test('dispose completes pending onReady normally (no error)', () async {
      final future = manager.onReady;
      await manager.dispose();
      await expectLater(future, completes);
    });

    test('dispose completes pending onTimeout normally (no error)', () async {
      final future = manager.onTimeout;
      await manager.dispose();
      await expectLater(future, completes);
    });

    test('dispose closes onUpdated stream', () async {
      final done = Completer<void>();
      manager.onUpdated.listen((_) {}, onDone: done.complete);
      await manager.dispose();
      await expectLater(done.future, completes);
    });

    test('isDestroyed becomes true after dispose', () async {
      await manager.dispose();
      expect(manager.isDestroyed, isTrue);
    });

    test('post-dispose notifyReady is a no-op — does not throw', () async {
      await manager.dispose();
      expect(() => manager.notifyReady(), returnsNormally);
    });

    test('post-dispose notifyTimeout is a no-op — does not throw', () async {
      await manager.dispose();
      expect(() => manager.notifyTimeout(), returnsNormally);
    });

    test('post-dispose notifyUpdate is a no-op — does not throw', () async {
      await manager.dispose();
      expect(() => manager.notifyUpdate(['x']), returnsNormally);
    });

  });
}
