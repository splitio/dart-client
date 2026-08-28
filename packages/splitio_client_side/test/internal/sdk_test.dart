import 'package:splitio_commons/src/models/models.dart';
import 'package:splitio_client_side/src/internal/split_factory.dart';
import 'package:test/test.dart';

void main() {
  group('SplitFactory', () {
    group('NoOp factory (empty SDK key)', () {
      late SplitFactory factory;

      setUp(() {
        factory = SplitFactory.create(
            '', const SplitClientConfig(), const Key(matchingKey: 'test'));
      });

      tearDown(() async {
        await factory.destroy();
      });

      test('empty SDK key returns a NoOp factory', () {
        expect(factory, isNotNull);
      });

      test('NoOp client returns control for any flag', () {
        final client = factory.client(const Key(matchingKey: 'test'));
        final result = client.getTreatment('any_flag');
        expect(result, equals('control'));
      });

      test('NoOp client returns control for multiple flags', () {
        final client = factory.client(const Key(matchingKey: 'test'));
        final results = client.getTreatments(['flag_a', 'flag_b', 'flag_c']);
        expect(results, hasLength(3));
        for (final r in results) {
          expect(r, equals('control'));
        }
      });

      test('NoOp client getTreatmentsByFlagSets returns empty', () {
        final client = factory.client(const Key(matchingKey: 'test'));
        final results = client.getTreatmentsByFlagSets(['set_a']);
        expect(results, isEmpty);
      });

      test('NoOp client track returns false', () {
        final client = factory.client(const Key(matchingKey: 'test'));
        final tracked = client.track('purchase', 'user', value: 9.99);
        expect(tracked, isFalse);
      });

      test('NoOp manager returns empty lists', () {
        final manager = factory.manager();
        expect(manager.split('any'), isNull);
        expect(manager.splits(), isEmpty);
        expect(manager.names(), isEmpty);
      });
    });

    group('Valid SDK key', () {
      late SplitFactory factory;

      setUp(() {
        factory = SplitFactory.create(
          'valid-sdk-key-123',
          const SplitClientConfig(
            sync: SyncConfig(readyTimeout: 0),
          ),
          const Key(matchingKey: 'test'),
        );
      });

      tearDown(() async {
        await factory.destroy();
      });

      test('valid SDK key creates a working factory without throwing', () {
        expect(factory, isNotNull);
      });

      test('factory.client() returns a SplitClient', () {
        final client = factory.client(const Key(matchingKey: 'test'));
        expect(client, isNotNull);
      });

      test('factory.manager() returns a SplitManager', () {
        final manager = factory.manager();
        expect(manager, isNotNull);
      });

      test('factory.userConsent() returns a UserConsentManager', () {
        final consent = factory.userConsent();
        expect(consent, isNotNull);
        expect(consent.status, equals(ConsentStatus.granted));
      });

      test('factory.destroy() completes without error', () async {
        final f = SplitFactory.create(
          'another-key',
          const SplitClientConfig(sync: SyncConfig(readyTimeout: 0)),
          const Key(matchingKey: 'test'),
        );
        await expectLater(f.destroy(), completes);
      });

      test('client returns control for flags before sync completes', () {
        final client = factory.client(const Key(matchingKey: 'test'));
        final result = client.getTreatment('some_flag');
        expect(result, equals('control'));
      });

      test('bootstrap key returns the same default client instance', () {
        // Bootstrap key was 'test'; asking for it again yields the pre-built
        // default client rather than a fresh one.
        final a = factory.client(const Key(matchingKey: 'test'));
        final b = factory.client(const Key(matchingKey: 'test'));
        expect(identical(a, b), isTrue);
      });

      test('non-bootstrap keys return the same cached client instance', () {
        // Per spec §8.5: the factory caches issued clients by instance ID;
        // subsequent factory.client(sameKey) calls return the same instance.
        final a = factory.client(const Key(matchingKey: 'other'));
        final b = factory.client(const Key(matchingKey: 'other'));
        expect(identical(a, b), isTrue);
      });

      test(
        'requesting a new key does not throw even if memberships sync fails',
        () {
          // With an unreachable network in tests, the fire-and-forget
          // syncMembershipsForKey call will fail, but client() must still
          // succeed synchronously.
          expect(
            () => factory.client(const Key(matchingKey: 'brand_new_key')),
            returnsNormally,
          );
        },
      );

      test('repeated calls for the same non-bootstrap key do not throw', () {
        // Even if the on-demand memberships fetch dedupes on the first call,
        // subsequent client(sameKey) invocations must remain safe.
        expect(
          () {
            for (var i = 0; i < 3; i++) {
              factory.client(const Key(matchingKey: 'repeated_key'));
            }
          },
          returnsNormally,
        );
      });
    });

    group('UserConsentManager', () {
      test('default consent status is granted', () {
        final factory = SplitFactory.create(
          '',
          const SplitClientConfig(),
          const Key(matchingKey: 'test'),
        );
        final consent = factory.userConsent();
        expect(consent.status, equals(ConsentStatus.granted));
      });

      test('consent status can be changed', () {
        final factory = SplitFactory.create(
          '',
          const SplitClientConfig(),
          const Key(matchingKey: 'test'),
        );
        final consent = factory.userConsent();
        expect(consent.status, equals(ConsentStatus.granted));
        consent.setStatus(ConsentStatus.declined);
        expect(consent.status, equals(ConsentStatus.declined));
        consent.setStatus(ConsentStatus.granted);
        expect(consent.status, equals(ConsentStatus.granted));
      });
    });
  });
}
