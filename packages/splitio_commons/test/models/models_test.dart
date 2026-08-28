import 'package:splitio_commons/src/models/models.dart';
import 'package:test/test.dart';

void main() {
  group('Key', () {
    test('two Keys with same matchingKey and null bucketingKey are equal', () {
      final a = Key(matchingKey: 'user-1');
      final b = Key(matchingKey: 'user-1');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two Keys with same matchingKey and same bucketingKey are equal', () {
      final a = Key(matchingKey: 'user-1', bucketingKey: 'bucket-1');
      final b = Key(matchingKey: 'user-1', bucketingKey: 'bucket-1');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('Keys with different matchingKey are not equal', () {
      final a = Key(matchingKey: 'user-1');
      final b = Key(matchingKey: 'user-2');
      expect(a, isNot(equals(b)));
    });

    test('Keys with different bucketingKey are not equal', () {
      final a = Key(matchingKey: 'user-1', bucketingKey: 'bucket-1');
      final b = Key(matchingKey: 'user-1', bucketingKey: 'bucket-2');
      expect(a, isNot(equals(b)));
    });

    test('Key with bucketingKey differs from one without', () {
      final a = Key(matchingKey: 'user-1');
      final b = Key(matchingKey: 'user-1', bucketingKey: 'bucket-1');
      expect(a, isNot(equals(b)));
    });

    test('toString includes both fields', () {
      final key = Key(matchingKey: 'mk', bucketingKey: 'bk');
      expect(key.toString(), contains('mk'));
      expect(key.toString(), contains('bk'));
    });
  });

  group('EvaluationResult', () {
    test('constructs with required fields', () {
      const result = EvaluationResult(treatment: 'on');
      expect(result.treatment, equals('on'));
      expect(result.config, isNull);
    });

    test('constructs with config', () {
      const result = EvaluationResult(
        treatment: 'on',
        config: '{"color":"red"}',
      );
      expect(result.treatment, equals('on'));
      expect(result.config, equals('{"color":"red"}'));
    });
  });

  group('SplitView', () {
    test('constructs with required fields and defaults', () {
      final view = SplitView(
        name: 'feature_x',
        trafficType: 'user',
        killed: false,
        treatments: ['on', 'off'],
        changeNumber: 100,
        defaultTreatment: 'off',
      );
      expect(view.name, equals('feature_x'));
      expect(view.trafficType, equals('user'));
      expect(view.killed, isFalse);
      expect(view.treatments, equals(['on', 'off']));
      expect(view.changeNumber, equals(100));
      expect(view.defaultTreatment, equals('off'));
      expect(view.configs, isEmpty);
      expect(view.sets, isEmpty);
      expect(view.impressionsDisabled, isFalse);
    });

    test('constructs with all optional fields', () {
      final view = SplitView(
        name: 'feature_y',
        trafficType: 'account',
        killed: true,
        treatments: ['v1', 'v2', 'control'],
        changeNumber: 200,
        defaultTreatment: 'control',
        configs: {'v1': '{"size":10}'},
        sets: ['set_a', 'set_b'],
        impressionsDisabled: true,
      );
      expect(view.configs, equals({'v1': '{"size":10}'}));
      expect(view.sets, equals(['set_a', 'set_b']));
      expect(view.impressionsDisabled, isTrue);
    });
  });

  group('SplitClientConfig', () {
    test('has sensible defaults', () {
      const config = SplitClientConfig();
      expect(config.impressionsMode, equals(ImpressionsMode.optimized));
      expect(config.userConsent, equals(ConsentStatus.granted));
      expect(config.impressionListener, isNull);
      expect(config.logLevel, equals(LogLevel.info));
      expect(config.sync.featureFlagsPollingRate, equals(60));
      expect(config.sync.segmentsPollingRate, equals(60));
      expect(config.sync.impressionsPushRate, equals(300));
      expect(config.sync.eventsPushRate, equals(60));
      expect(config.sync.readyTimeout, equals(10));
    });
  });

  group('CombiningMatcher', () {
    test('stores the provided delegates list', () {
      const inner = [
        AttributeMatcher(delegate: AllKeysMatcher()),
        AttributeMatcher(
          delegate: WhitelistMatcher(whitelist: {'user1'}),
        ),
      ];
      const combining = CombiningMatcher(delegates: inner);

      expect(combining.delegates, hasLength(2));
      expect(combining.delegates[0].delegate, isA<AllKeysMatcher>());
      expect(combining.delegates[1].delegate, isA<WhitelistMatcher>());
    });

    test('defaults combiner to AND', () {
      const combining = CombiningMatcher(delegates: []);
      expect(combining.combiner, equals(CombinerEnum.and));
    });

    test('accepts an empty delegates list', () {
      const combining = CombiningMatcher(delegates: []);
      expect(combining.delegates, isEmpty);
    });
  });

  group('SyncConfig.normalized()', () {
    test('clamps polling rates below 30 to 30', () {
      const config = SyncConfig(
        featureFlagsPollingRate: 5,
        segmentsPollingRate: 10,
        impressionsPushRate: 1,
        eventsPushRate: 29,
      );
      final normalized = config.normalized();
      expect(normalized.featureFlagsPollingRate, equals(30));
      expect(normalized.segmentsPollingRate, equals(30));
      expect(normalized.impressionsPushRate, equals(30));
      expect(normalized.eventsPushRate, equals(30));
    });

    test('preserves values at or above 30', () {
      const config = SyncConfig(
        featureFlagsPollingRate: 30,
        segmentsPollingRate: 60,
        impressionsPushRate: 300,
        eventsPushRate: 120,
      );
      final normalized = config.normalized();
      expect(normalized.featureFlagsPollingRate, equals(30));
      expect(normalized.segmentsPollingRate, equals(60));
      expect(normalized.impressionsPushRate, equals(300));
      expect(normalized.eventsPushRate, equals(120));
    });

    test('clamps negative readyTimeout to 0', () {
      const config = SyncConfig(readyTimeout: -5);
      final normalized = config.normalized();
      expect(normalized.readyTimeout, equals(0));
    });

    test('preserves non-negative readyTimeout', () {
      const config = SyncConfig(readyTimeout: 15);
      final normalized = config.normalized();
      expect(normalized.readyTimeout, equals(15));
    });

    test('preserves serviceEndpoints', () {
      const endpoints = ServiceEndpoints(sdkUrl: 'https://custom.io');
      const config = SyncConfig(serviceEndpoints: endpoints);
      final normalized = config.normalized();
      expect(normalized.serviceEndpoints?.sdkUrl, equals('https://custom.io'));
    });

    test('streamingUrl defaults to null', () {
      const endpoints = ServiceEndpoints(sdkUrl: 'https://custom.io');
      expect(endpoints.streamingUrl, isNull);
    });

    test('preserves streamingUrl through normalized', () {
      const endpoints =
          ServiceEndpoints(streamingUrl: 'https://streaming.custom.io');
      const config = SyncConfig(serviceEndpoints: endpoints);
      final normalized = config.normalized();
      expect(normalized.serviceEndpoints?.streamingUrl,
          equals('https://streaming.custom.io'));
    });

    test('streamingEnabled defaults to true', () {
      const config = SyncConfig();
      expect(config.streamingEnabled, isTrue);
    });

    test('streamingEnabled respects explicit false', () {
      const config = SyncConfig(streamingEnabled: false);
      expect(config.streamingEnabled, isFalse);
    });

    test('normalized preserves streamingEnabled', () {
      const config = SyncConfig(streamingEnabled: false);
      final normalized = config.normalized();
      expect(normalized.streamingEnabled, isFalse);
    });
  });
}
