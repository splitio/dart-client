import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

void main() {
  group('sdk_single public API re-exports', () {
    test('SplitFactory is accessible', () {
      final factory = SplitFactory.create(
          '', const SplitClientConfig(), const Key(matchingKey: 'test'));
      expect(factory, isNotNull);
    });

    test('SplitClient is accessible via factory', () {
      final factory = SplitFactory.create(
          '', const SplitClientConfig(), const Key(matchingKey: 'test'));
      final client = factory.client();
      expect(client, isA<SplitClient>());
    });

    test('SplitManager is accessible via factory', () {
      final factory = SplitFactory.create(
          '', const SplitClientConfig(), const Key(matchingKey: 'test'));
      final manager = factory.manager();
      expect(manager, isA<SplitManager>());
    });

    test('EvaluationResult is accessible', () {
      const result = EvaluationResult(treatment: 'on');
      expect(result.treatment, equals('on'));
      expect(result.config, isNull);
    });

    test('Key is accessible', () {
      const key = Key(matchingKey: 'user1', bucketingKey: 'bucket1');
      expect(key.matchingKey, equals('user1'));
      expect(key.bucketingKey, equals('bucket1'));
    });

    test('Target is accessible', () {
      const target = Target(
        key: Key(matchingKey: 'user1'),
        attributes: {'plan': 'premium'},
      );
      expect(target.key.matchingKey, equals('user1'));
      expect(target.attributes['plan'], equals('premium'));
    });

    test('SplitView is accessible', () {
      const view = SplitView(
        name: 'my_flag',
        trafficType: 'user',
        killed: false,
        treatments: ['on', 'off'],
        changeNumber: 1,
        defaultTreatment: 'off',
      );
      expect(view.name, equals('my_flag'));
      expect(view.treatments, contains('on'));
    });

    test('SplitClientConfig is accessible', () {
      const config = SplitClientConfig(
        impressionsMode: ImpressionsMode.debug,
      );
      expect(config.impressionsMode, equals(ImpressionsMode.debug));
    });

    test('ConsentStatus enum is accessible', () {
      expect(ConsentStatus.granted, isNotNull);
      expect(ConsentStatus.declined, isNotNull);
      expect(ConsentStatus.unknown, isNotNull);
    });

    test('whenReady / whenTimeout / whenUpdated are accessible on SplitClient', () {
      final factory = SplitFactory.create(
          '', const SplitClientConfig(), const Key(matchingKey: 'test'));
      final client = factory.client(const Key(matchingKey: 'test'));
      expect(client.whenReady, isNotNull);
      expect(client.whenTimeout, isNotNull);
      expect(client.whenUpdated, isNotNull);
    });
  });

  group('sdk_single NoOp behavior (verifies re-export wiring)', () {
    late SplitFactory factory;

    setUp(() {
      factory = SplitFactory.create(
          '', const SplitClientConfig(), const Key(matchingKey: 'test'));
    });

    tearDown(() async {
      await factory.destroy();
    });

    test('empty key produces NoOp client returning control', () {
      final client = factory.client();
      final result = client.getTreatment('feature_x');
      expect(result, equals('control'));
    });

    test('NoOp manager returns null for split lookup', () {
      final manager = factory.manager();
      expect(manager.split('anything'), isNull);
    });

    test('NoOp manager returns empty names list', () {
      final manager = factory.manager();
      expect(manager.names(), isEmpty);
    });

    test('UserConsentManager is accessible and defaults to granted', () {
      final consent = factory.userConsent();
      expect(consent.status, equals(ConsentStatus.granted));
    });

    test('destroy completes without error', () async {
      await expectLater(factory.destroy(), completes);
    });
  });
}
