// Key validation e2e (QA release report vs Node SDK, spec §16): matchingKey
// / bucketingKey MUST be trimmed, non-empty after trimming, and limited to
// 250 chars (previously 1024, and not trimmed at all). The trimmed value
// MUST flow through to evaluation, bucketing, impressions and events.
//
// `test_flag_whitelist` (shared_data/basic_evaluation_suite) whitelists
// "user_a" -> "on". `test_flag_killed` is killed with defaultTreatment
// "off", so it returns a deterministic "off" for ANY valid key — used to
// prove a 250-char key reaches the evaluator rather than being rejected,
// without depending on bucketing/rollout math.
import 'dart:async';
import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart' as cs;
import 'package:splitio_server_side/splitio_server_side.dart' as ss;
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

String _baseUrl(MockBackend backend) => backend.url.endsWith('/')
    ? backend.url.substring(0, backend.url.length - 1)
    : backend.url;

void main() {
  group('Key validation e2e — client-side', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    cs.SplitClientConfig config(String baseUrl) => cs.SplitClientConfig(
          sync: cs.SyncConfig(
            serviceEndpoints:
                cs.ServiceEndpoints(sdkUrl: baseUrl, eventsUrl: baseUrl),
            featureFlagsPollingRate: 9999,
            segmentsPollingRate: 9999,
            impressionsPushRate: 9999,
            eventsPushRate: 9999,
          ),
          impressionsMode: cs.ImpressionsMode.debug,
          logLevel: cs.LogLevel.error,
        );

    Future<cs.SplitFactory> buildFactory(Object key) async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      return cs.SplitFactory.create(
          'fake-api-key', config(_baseUrl(backend)), key);
    }

    test(
        'default key with surrounding whitespace evaluates like the trimmed '
        'key and the flushed impression/event carry the trimmed value',
        () async {
      final factory = await buildFactory(const cs.Key(matchingKey: ' user_a '));
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      expect(client.getTreatment('test_flag_whitelist'), 'on',
          reason: '"user_a" is whitelisted — a surrounding-whitespace key MUST '
              'evaluate the same as the trimmed key');

      final tracked = client.track('click', 'user');
      expect(tracked, isTrue);

      await factory.destroy();

      final impressions = backend.postedImpressionsFlat
          .where((imp) => imp['f'] == 'test_flag_whitelist')
          .toList();
      expect(impressions, hasLength(1));
      expect(impressions.first['k'], 'user_a',
          reason: 'impression key MUST be the trimmed matching key');

      final events = backend.postedEvents;
      expect(events, hasLength(1));
      expect(events.first['key'], 'user_a',
          reason: 'tracked event key MUST be the trimmed matching key');
    });

    test('251-char default key produces a NoOp factory (no /splitChanges)',
        () async {
      final startCount = backend.splitChangesRequests.length;

      final factory = await buildFactory(cs.Key(matchingKey: 'a' * 251));

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(factory.client().getTreatment('test_flag_killed'), 'control');
      expect(backend.splitChangesRequests.length, startCount);

      await factory.destroy();
    });

    test('whitespace-only default key produces a NoOp factory', () async {
      final startCount = backend.splitChangesRequests.length;

      final factory = await buildFactory(const cs.Key(matchingKey: '   '));

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(factory.client().getTreatment('test_flag_killed'), 'control');
      expect(backend.splitChangesRequests.length, startCount);

      await factory.destroy();
    });

    test('250-char default key is valid and the SDK becomes ready', () async {
      final factory = await buildFactory(cs.Key(matchingKey: 'a' * 250));
      final client = factory.client();

      await expectLater(
          client.whenReady().timeout(const Duration(seconds: 5)), completes);
      expect(client.getTreatment('test_flag_killed'), 'off',
          reason: 'a 250-char key MUST reach the real evaluator, not '
              'control');

      await factory.destroy();
    });

    test(
        'client(" user_1 ") returns the same cached instance as '
        'client("user_1")', () async {
      final factory = await buildFactory('user_1');

      final viaWhitespace = factory.client(' user_1 ');
      final viaTrimmed = factory.client('user_1');

      expect(identical(viaWhitespace, viaTrimmed), isTrue,
          reason: 'trimming MUST happen before the per-key client cache is '
              'keyed, so equivalent keys resolve to the same instance');

      await factory.destroy();
    });

    test(
        'repeated client(invalidKey) calls reuse one shared NoOp client '
        'and never fetch /memberships', () async {
      final factory = await buildFactory('user_1');
      await factory.client().whenReady().timeout(const Duration(seconds: 5));
      final startCount = backend.membershipsRequests.length;

      final first = factory.client('');
      final noOps = [
        for (final bad in <Object>[
          '   ',
          'a' * 251,
          <int>[1]
        ])
          factory.client(bad),
      ];

      for (final c in noOps) {
        expect(identical(c, first), isTrue,
            reason: 'every invalid key MUST resolve to the same NoOp client '
                'so repeated calls do not accumulate instances');
      }
      expect(identical(first, factory.client()), isFalse);
      expect(first.getTreatment('test_flag_killed'), 'control');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(backend.membershipsRequests.length, startCount);

      await factory.destroy();
    });

    test(
        'client(invalidKey) first requested after destroy() never fires '
        'whenTimeout()', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      final baseUrl = _baseUrl(backend);
      final factory = cs.SplitFactory.create(
          'fake-api-key',
          cs.SplitClientConfig(
            sync: cs.SyncConfig(
              serviceEndpoints:
                  cs.ServiceEndpoints(sdkUrl: baseUrl, eventsUrl: baseUrl),
              readyTimeout: 1,
            ),
            logLevel: cs.LogLevel.error,
          ),
          'user_1');
      await factory.client().whenReady().timeout(const Duration(seconds: 5));
      await factory.destroy();

      final noOp = factory.client('');
      var timedOut = false;
      unawaited(noOp.whenTimeout().then((_) => timedOut = true));
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(timedOut, isFalse,
          reason: 'a NoOp created after destroy() MUST NOT arm a '
              'readyTimeout timer that nothing cancels');
    });
  });

  group('Key validation e2e — server-side', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    ss.SplitClientConfig config() {
      final baseUrl = _baseUrl(backend);
      return ss.SplitClientConfig(
        sync: ss.SyncConfig(
          serviceEndpoints:
              ss.ServiceEndpoints(sdkUrl: baseUrl, eventsUrl: baseUrl),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
          eventsPushRate: 9999,
        ),
        impressionsMode: ss.ImpressionsMode.debug,
        installSignalHandler: false,
        logLevel: ss.LogLevel.error,
      );
    }

    Future<ss.SplitFactory> buildFactory() async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/basic_evaluation_suite',
      );
      // basic_evaluation_suite's `test_flag_segment` references the
      // `beta_users` segment; server-side readiness requires every
      // referenced segment to sync via /segmentChanges (stubFromFixtures
      // only wires up /memberships, which is client-side only).
      backend.stubSegmentChanges();
      return ss.SplitFactory.create('fake-api-key', config());
    }

    test(
        'per-call key with surrounding whitespace evaluates like the '
        'trimmed key and the flushed impression/event carry the trimmed '
        'value', () async {
      final factory = await buildFactory();
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      final whitespaceTreatment =
          client.getTreatment(' user_a ', 'test_flag_whitelist');
      final trimmedTreatment =
          client.getTreatment('user_a', 'test_flag_whitelist');
      expect(whitespaceTreatment, 'on');
      expect(whitespaceTreatment, trimmedTreatment);

      final tracked = client.track(' user_a ', 'user', 'click');
      expect(tracked, isTrue);

      await factory.destroy();

      final impressions = backend.postedImpressionsFlat
          .where((imp) => imp['f'] == 'test_flag_whitelist')
          .toList();
      expect(impressions, isNotEmpty);
      expect(impressions.first['k'], 'user_a',
          reason: 'impression key MUST be the trimmed matching key');

      final events = backend.postedEvents;
      expect(events, hasLength(1));
      expect(events.first['key'], 'user_a',
          reason: 'tracked event key MUST be the trimmed matching key');
    });

    test(
        '251-char key returns control from getTreatment and false from '
        'track', () async {
      final factory = await buildFactory();
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      final longKey = 'a' * 251;
      expect(client.getTreatment(longKey, 'test_flag_killed'), 'control');
      expect(client.track(longKey, 'user', 'click'), isFalse);

      await factory.destroy();
      expect(backend.postedEvents, isEmpty);
    });

    test('250-char key evaluates normally (reaches the real evaluator)',
        () async {
      final factory = await buildFactory();
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      final key = 'a' * 250;
      expect(client.getTreatment(key, 'test_flag_killed'), 'off');

      await factory.destroy();
    });

    test(
        'whitespace-only key returns control from getTreatment and false '
        'from track', () async {
      final factory = await buildFactory();
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      expect(client.getTreatment('   ', 'test_flag_killed'), 'control');
      expect(client.track('   ', 'user', 'click'), isFalse);

      await factory.destroy();
      expect(backend.postedEvents, isEmpty);
    });
  });
}
