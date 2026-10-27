import 'dart:async';

import 'package:splitio_commons/src/events/events.dart';
import 'package:test/test.dart';

void main() {
  group('ClientUpdates', () {
    late EventsManager manager;

    setUp(() {
      manager = EventsManager();
      // ClientUpdates tests only exercise forwarding/close semantics, not
      // readiness gating (which EventsManager owns and events_test.dart
      // covers) — mark ready up front so notifyUpdate below actually emits.
      manager.notifyReady();
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('forwards updates from the shared EventsManager', () async {
      final updates = ClientUpdates(manager.onUpdated);
      final received = <List<String>>[];
      updates.stream.listen(received.add);

      manager.notifyUpdate(['flag_a']);
      await Future<void>.delayed(Duration.zero);

      expect(received, [
        ['flag_a']
      ]);
      await updates.close();
    });

    test('close() ends its stream without affecting other clients', () async {
      final destroyed = ClientUpdates(manager.onUpdated);
      final kept = ClientUpdates(manager.onUpdated);
      final keptReceived = <List<String>>[];
      kept.stream.listen(keptReceived.add);
      final destroyedDone = destroyed.stream.toList();

      await destroyed.close();
      manager.notifyUpdate(['flag_a']);
      await Future<void>.delayed(Duration.zero);

      expect(await destroyedDone, isEmpty);
      expect(keptReceived, [
        ['flag_a']
      ]);
      await kept.close();
    });

    test('a listener added after close() receives onDone immediately',
        () async {
      final updates = ClientUpdates(manager.onUpdated);
      await updates.close();

      await expectLater(updates.stream, emitsDone);
    });

    test('close() is idempotent', () async {
      final updates = ClientUpdates(manager.onUpdated);
      await updates.close();
      await expectLater(updates.close(), completes);
    });

    group('close() with in-flight updates raises no uncaught error', () {
      // Runs [body] in a guarded zone and returns every error that escaped
      // it, so a StateError from adding to the closed controller would
      // surface here instead of in the zone's uncaught handler.
      Future<List<Object>> uncaughtErrors(Future<void> Function() body) async {
        final errors = <Object>[];
        await runZonedGuarded(body, (e, _) => errors.add(e));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return errors;
      }

      test('updates queued on the source before close()', () async {
        final errors = await uncaughtErrors(() async {
          final updates = ClientUpdates(manager.onUpdated);
          updates.stream.listen((_) {});
          manager.notifyUpdate(['flag_a']);
          manager.notifyUpdate(['flag_b']);
          unawaited(updates.close());
        });

        expect(errors, isEmpty);
      });

      test('close() called by a subscriber mid-burst', () async {
        final errors = await uncaughtErrors(() async {
          final updates = ClientUpdates(manager.onUpdated);
          updates.stream.listen((_) => updates.close());
          for (var i = 0; i < 5; i++) {
            manager.notifyUpdate(['flag_$i']);
          }
        });

        expect(errors, isEmpty);
      });

      test('close() called by a sibling listener during source dispatch',
          () async {
        final errors = await uncaughtErrors(() async {
          final updates = ClientUpdates(manager.onUpdated);
          updates.stream.listen((_) {});
          manager.onUpdated.listen((_) => updates.close());
          for (var i = 0; i < 5; i++) {
            manager.notifyUpdate(['flag_$i']);
          }
        });

        expect(errors, isEmpty);
      });

      test('close() racing EventsManager.dispose() with pending updates',
          () async {
        final errors = await uncaughtErrors(() async {
          final updates = ClientUpdates(manager.onUpdated);
          updates.stream.listen((_) {});
          manager.notifyUpdate(['flag_a']);
          unawaited(manager.dispose());
          unawaited(updates.close());
        });

        expect(errors, isEmpty);
      });
    });

    test('closes when the EventsManager is disposed', () async {
      final updates = ClientUpdates(manager.onUpdated);
      final done = updates.stream.toList();

      await manager.dispose();

      expect(await done.timeout(const Duration(seconds: 1)), isEmpty);
    });
  });
}
