import 'dart:io';

import 'package:splitio_server_side/splitio_server_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

/// Server-side bucketing-key evaluation + impression recording (PR review
/// thread): a server-side `getTreatment(Key(matchingKey, bucketingKey), flag)`
/// call MUST hash on the bucketing key (not the matching key) when present,
/// and the recorded impression MUST carry that bucketing key.
///
/// `flag_bucketing_key_split` (shared_data/engine_features_suite) is a
/// hash-based 50/50 ALL_KEYS rollout (seed 5555, algo murmur3). With that
/// seed, matching key "bob" alone buckets to "off", while bucketing on
/// "alice" (seed 5555) buckets to "on" — this divergence is already relied
/// on by `shared_evaluation_test.dart`'s client-side run of
/// `engine_features_suite/test_cases.json` ("bucketingKey changes bucket
/// assignment" cases), so the same two keys are reused here, chosen so that
/// matching-key-only and matching+bucketing-key resolve to different
/// treatments.
void main() {
  group('Server-side bucketing key e2e', () {
    late MockBackend backend;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      await backend.shutdown();
    });

    test(
        'getTreatment with a Key(matchingKey, bucketingKey) hashes on the '
        'bucketing key and the recorded impression carries it', () async {
      backend.stubFromFixtures(
        '${Directory.current.path}/test/shared_data/engine_features_suite',
      );

      final baseUrl = backend.url.endsWith('/')
          ? backend.url.substring(0, backend.url.length - 1)
          : backend.url;

      final config = SplitClientConfig(
        sync: SyncConfig(
          serviceEndpoints: ServiceEndpoints(
            sdkUrl: baseUrl,
            eventsUrl: baseUrl,
          ),
          featureFlagsPollingRate: 9999,
          segmentsPollingRate: 9999,
          impressionsPushRate: 9999,
        ),
        impressionsMode: ImpressionsMode.debug,
        installSignalHandler: false,
        logLevel: LogLevel.warning,
      );

      final factory = SplitFactory.create('fake-api-key', config);
      final client = factory.client();
      await client.whenReady().timeout(const Duration(seconds: 5));

      // Matching-key-only: hashes on "bob" directly -> "off".
      final matchingKeyOnlyTreatment =
          client.getTreatment('bob', 'flag_bucketing_key_split');
      expect(matchingKeyOnlyTreatment, 'off');

      // Matching key "bob" + bucketing key "alice": hashes on "alice" ->
      // "on", which diverges from the matching-key-only result above.
      final withBucketingKeyTreatment = client.getTreatment(
        const Key(matchingKey: 'bob', bucketingKey: 'alice'),
        'flag_bucketing_key_split',
      );
      expect(withBucketingKeyTreatment, 'on');
      expect(withBucketingKeyTreatment, isNot(matchingKeyOnlyTreatment));

      await factory.destroy();

      final posted = backend.postedImpressionsFlat
          .where((imp) => imp['f'] == 'flag_bucketing_key_split')
          .toList();
      expect(posted, hasLength(2));

      final matchingKeyOnlyImpression =
          posted.firstWhere((imp) => !imp.containsKey('b'));
      expect(matchingKeyOnlyImpression['k'], 'bob');
      expect(matchingKeyOnlyImpression['t'], 'off');
      expect(matchingKeyOnlyImpression.containsKey('b'), isFalse,
          reason:
              'no bucketing key was supplied, so "b" must be absent from the wire payload');

      final withBucketingKeyImpression =
          posted.firstWhere((imp) => imp.containsKey('b'));
      expect(withBucketingKeyImpression['k'], 'bob');
      expect(withBucketingKeyImpression['b'], 'alice');
      expect(withBucketingKeyImpression['t'], 'on');
    });
  });
}
