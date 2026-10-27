import 'dart:async';

import 'package:splitio_client_side/src/internal/split_factory.dart';
import 'package:splitio_commons/src/models/config.dart';
import 'package:splitio_commons/src/models/key.dart';
import 'package:test/test.dart';

void main() {
  group('SplitFactory.create — NoOp on invalid input', () {
    test('returns NoOp on empty sdkKey', () async {
      final f = SplitFactory.create(
          '', const SplitClientConfig(), const Key(matchingKey: 'k'));
      expect(
          f.client(const Key(matchingKey: 'k')).getTreatment('any'), 'control');
      await f.destroy();
    });

    test('returns NoOp on whitespace-only sdkKey', () async {
      final f = SplitFactory.create(
          '   ', const SplitClientConfig(), const Key(matchingKey: 'k'));
      expect(
          f.client(const Key(matchingKey: 'k')).getTreatment('any'), 'control');
      await f.destroy();
    });

    test('returns NoOp on empty matchingKey', () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), const Key(matchingKey: ''));
      expect(
          f.client(const Key(matchingKey: 'k')).getTreatment('any'), 'control');
      await f.destroy();
    });

    test('returns NoOp on over-length matchingKey', () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), Key(matchingKey: 'a' * 1025));
      expect(
          f.client(const Key(matchingKey: 'a')).getTreatment('x'), 'control');
      await f.destroy();
    });
  });

  group('SplitFactory NoOp — whenX on invalid factory', () {
    test('NoOp client whenReady() never completes', () async {
      final f = SplitFactory.create(
          '', const SplitClientConfig(), const Key(matchingKey: 'k'));
      final client = f.client();
      await expectLater(
          client.whenReady().timeout(const Duration(milliseconds: 200)),
          throwsA(isA<TimeoutException>()),
          reason: "A NoOp client's whenReady() MUST NOT complete (spec §7)");
      await f.destroy();
    });

    test('NoOp client whenTimeout() completes after readyTimeout', () async {
      final f = SplitFactory.create(
          '',
          const SplitClientConfig(sync: SyncConfig(readyTimeout: 1)),
          const Key(matchingKey: 'k'));
      final client = f.client();
      await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 3)), completes,
          reason: "A NoOp client's whenTimeout() MUST complete after "
              'readyTimeout (spec §7, §8.2)');
      await f.destroy();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
        'NoOp factory destroy() before readyTimeout prevents whenTimeout '
        'from firing', () async {
      final f = SplitFactory.create(
          '',
          const SplitClientConfig(sync: SyncConfig(readyTimeout: 1)),
          const Key(matchingKey: 'k'));
      final client = f.client();
      await f.destroy();
      await expectLater(
          client.whenTimeout().timeout(const Duration(seconds: 2)),
          throwsA(isA<TimeoutException>()),
          reason: 'destroy() before readyTimeout MUST cancel the timer');
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('NoOp client whenUpdated() returns empty stream', () async {
      final f = SplitFactory.create(
          '', const SplitClientConfig(), const Key(matchingKey: 'k'));
      final client = f.client();
      final events = <List<String>>[];
      final sub = client.whenUpdated().listen(events.add);
      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
      await sub.cancel();
      await f.destroy();
    });
  });

  group('SplitFactory.destroy — JS-parity behavior', () {
    test('factory.destroy() completes without error', () async {
      final f = SplitFactory.create('sdk-key', const SplitClientConfig(),
          const Key(matchingKey: 'user1'));
      // Don't wait for ready - just test that destroy completes
      await expectLater(f.destroy(), completes);
    });

    test('factory.destroy() is idempotent', () async {
      final f = SplitFactory.create('sdk-key', const SplitClientConfig(),
          const Key(matchingKey: 'user1'));
      await f.destroy();
      await expectLater(f.destroy(), completes,
          reason: 'Second destroy call should be a no-op');
    });

    test('track on cached shared client after factory.destroy returns false',
        () async {
      final mainKey = const Key(matchingKey: 'main_user');
      final sharedKey = const Key(matchingKey: 'shared_user');
      final f =
          SplitFactory.create('sdk-key', const SplitClientConfig(), mainKey);

      // Get a reference to a shared client before destroy
      final sharedClient = f.client(sharedKey);

      await f.destroy();

      // After factory.destroy(), the cached shared client should reject track
      final trackResult = sharedClient.track('click', 'user');
      expect(trackResult, isFalse,
          reason:
              'Shared client track after factory.destroy should return false');
    });

    test('shared client getTreatment after factory.destroy returns control',
        () async {
      final mainKey = const Key(matchingKey: 'main_user');
      final sharedKey = const Key(matchingKey: 'shared_user');
      final f =
          SplitFactory.create('sdk-key', const SplitClientConfig(), mainKey);

      final sharedClient = f.client(sharedKey);

      await f.destroy();

      final treatment = sharedClient.getTreatment('some_flag');
      expect(treatment, equals('control'),
          reason: 'getTreatment after factory.destroy should return control');
    });

    test('main client getTreatment after factory.destroy returns control',
        () async {
      final mainKey = const Key(matchingKey: 'main_user');
      final f =
          SplitFactory.create('sdk-key', const SplitClientConfig(), mainKey);

      final mainClient = f.client(mainKey);

      await f.destroy();

      final treatment = mainClient.getTreatment('some_flag');
      expect(treatment, equals('control'),
          reason:
              'Main client getTreatment after factory.destroy should return control');
    });

    test('mainClient.destroy() does not affect shared clients (JS parity)',
        () async {
      // Per spec §8.5: mainClient.destroy() marks only the main client
      // destroyed. The factory and shared clients MUST remain operational.
      // factory.destroy() is NOT equivalent to mainClient.destroy().
      final mainKey = const Key(matchingKey: 'main_user');
      final sharedKey = const Key(matchingKey: 'shared_user');
      final f =
          SplitFactory.create('sdk-key', const SplitClientConfig(), mainKey);

      final sharedClient = f.client(sharedKey);

      await f.client().destroy();

      final trackResult = sharedClient.track('click', 'user');
      expect(trackResult, isTrue,
          reason: 'Shared client must remain operational after main destroy');

      await f.destroy();
    });
  });

  group('SplitFactory — String key shorthand', () {
    test(
        'create with String bootstrap key returns a working factory (not NoOp)',
        () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), 'CUSTOMER_ID');
      // Real factory (not NoOp) — client returns a real SplitClientImpl.
      // A NoOp client returns 'control' immediately without touching stores;
      // a real client also returns 'control' for an unknown flag but is a
      // different runtime type — assert identity of client('X') == client(Key).
      final viaString = f.client('CUSTOMER_ID');
      final viaKey = f.client(const Key(matchingKey: 'CUSTOMER_ID'));
      expect(identical(viaString, viaKey), isTrue,
          reason:
              'client("X") and client(Key(matchingKey:"X")) MUST return the same cached instance');
      await f.destroy();
    });

    test('factory.client(String) returns cached instance for equivalent Key',
        () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), const Key(matchingKey: 'boot'));
      final a = f.client('SHARED');
      final b = f.client(const Key(matchingKey: 'SHARED'));
      expect(identical(a, b), isTrue);
      await f.destroy();
    });

    test('create with non-String, non-Key key returns NoOp factory', () async {
      // 42 is neither String nor Key — must degrade to NoOp per §7.
      final f = SplitFactory.create('sdk-key', const SplitClientConfig(), 42);
      expect(f.client().getTreatment('any'), 'control',
          reason: 'NoOp factory client MUST return control');
      await f.destroy();
    });

    test('factory.client(invalidType) returns a NoOp client, not bootstrap',
        () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), const Key(matchingKey: 'boot'));
      final bootstrap = f.client();
      final viaInvalid = f.client(<int>[1]);
      expect(identical(viaInvalid, bootstrap), isFalse);
      expect(viaInvalid.getTreatment('any'), 'control');
      expect(viaInvalid.track('user', 'evt'), isFalse);
      await f.destroy();
    });

    test('factory.client(empty/whitespace/over-length) returns NoOp clients',
        () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), const Key(matchingKey: 'boot'));
      final bootstrap = f.client();
      for (final bad in <Object>[
        '',
        '   ',
        'x' * 251,
        const Key(matchingKey: 'ok', bucketingKey: ' ')
      ]) {
        final c = f.client(bad);
        expect(identical(c, bootstrap), isFalse);
        expect(c.getTreatment('any'), 'control');
      }
      await f.destroy();
    });

    test(
        'NoOp client from an invalid key: whenReady never completes, destroy '
        'cancels its timeout', () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), const Key(matchingKey: 'boot'));
      final c = f.client('');
      var ready = false;
      unawaited(c.whenReady().then((_) => ready = true));
      await c.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ready, isFalse);
      await f.destroy();
    });

    test('every invalid key resolves to one shared NoOp client', () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), const Key(matchingKey: 'boot'));
      final first = f.client('');
      for (final bad in <Object>[
        '   ',
        'x' * 251,
        <int>[1]
      ]) {
        expect(identical(f.client(bad), first), isTrue);
      }
      // Like a destroyed real client (spec §8.5), the shared NoOp stays
      // cached after its destroy() — no fresh instance is allocated.
      await first.destroy();
      expect(identical(f.client(''), first), isTrue);
      await f.destroy();
    });

    test(
        'a NoOp client first requested after destroy() never fires '
        'whenTimeout', () async {
      final f = SplitFactory.create(
          'sdk-key',
          const SplitClientConfig(sync: SyncConfig(readyTimeout: 1)),
          const Key(matchingKey: 'boot'));
      await f.destroy();
      await expectLater(
          f.client('').whenTimeout().timeout(const Duration(seconds: 2)),
          throwsA(isA<TimeoutException>()));
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('factory.client(num) is a distinct client keyed by toString()',
        () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), const Key(matchingKey: 'boot'));
      final viaNum = f.client(42);
      expect(identical(viaNum, f.client()), isFalse);
      expect(identical(viaNum, f.client('42')), isTrue);
      await f.destroy();
    });

    test('factory.client(null) returns the bootstrap client', () async {
      final f = SplitFactory.create(
          'sdk-key', const SplitClientConfig(), const Key(matchingKey: 'boot'));
      expect(identical(f.client(null), f.client()), isTrue);
      await f.destroy();
    });
  });
}
