import 'dart:convert';
import 'dart:io';

import 'package:splitio_client_side/splitio_client_side.dart';
import 'package:test/test.dart';

import 'helpers/mock_backend.dart';

void main() {
  final sharedDataDir = '${Directory.current.path}/test/shared_data';
  final suitesDir = Directory(sharedDataDir);

  if (!suitesDir.existsSync()) {
    fail('shared_data directory not found at $sharedDataDir');
  }

  final suites = suitesDir
      .listSync()
      .whereType<Directory>()
      .where((d) => File('${d.path}/test_cases.json').existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final suiteDir in suites) {
    final suiteName = suiteDir.uri.pathSegments.where((s) => s.isNotEmpty).last;

    group('Suite: $suiteName', () {
      late MockBackend backend;
      late SplitFactory factory;
      late SplitClient client;

      setUpAll(() async {
        backend = MockBackend();
        await backend.start();
        backend.stubFromFixtures(suiteDir.path);

        // Remove trailing slash from backend.url to avoid double slashes
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
          ),
          impressionsMode: ImpressionsMode.debug,
          logLevel: LogLevel.warning,
        );

        // Use user_c as the init key since it needs segment memberships fetched
        // TODO: SDK limitation - only fetches memberships for the init key
        final key = Key(matchingKey: 'user_c');
        factory = SplitFactory.create('fake-api-key', config, key);

        // Wait for SDK ready
        await factory
            .client(key)
            .whenReady()
            .timeout(const Duration(seconds: 5));
      });

      tearDownAll(() async {
        await backend.shutdown();
      });

      final testCasesFile = File('${suiteDir.path}/test_cases.json');
      final testCases = (jsonDecode(testCasesFile.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

      for (final tc in testCases) {
        final testName = tc['test'] as String;
        final method = tc['method'] as String;
        final userKey = tc['key'] as String;
        final bucketingKey = tc['bucketingKey'] as String?;
        final flagName = tc['flagName'] as String;
        final attributes = (tc['attributes'] as Map<String, dynamic>?)
                ?.cast<String, Object?>() ??
            {};
        final expectedTreatment = tc['expectedTreatment'] as String;
        final expectedConfig = tc['expectedConfig'] as String?;

        test(testName, () {
          final key = Key(
            matchingKey: userKey,
            bucketingKey: bucketingKey,
          );
          client = factory.client(key);

          switch (method) {
            case 'getTreatment':
              final result = client.getTreatment(
                flagName,
                attributes: attributes.isEmpty ? null : attributes,
              );
              expect(result, expectedTreatment,
                  reason: 'Treatment mismatch for "$testName"');
            case 'getTreatmentWithConfig':
              final result = client.getTreatmentWithConfig(
                flagName,
                attributes: attributes.isEmpty ? null : attributes,
              );
              expect(result.treatment, expectedTreatment,
                  reason: 'Treatment mismatch for "$testName"');
              expect(result.config, expectedConfig,
                  reason: 'Config mismatch for "$testName"');
            default:
              fail('Unknown method: $method');
          }
        });
      }

      test('flush on destroy posts correct impressions', () async {
        await factory.destroy();

        final posted = backend.postedImpressionsFlat;

        for (final tc in testCases) {
          final expected = tc['expectedImpression'];
          final flagName = tc['flagName'] as String;
          final testName = tc['test'] as String;

          if (expected == null) {
            final match = posted
                .where((imp) => imp['f'] == flagName && imp['k'] == tc['key']);
            expect(match, isEmpty,
                reason: 'No impression expected for "$testName"');
            continue;
          }

          final exp = expected as Map<String, dynamic>;

          final match = posted.where((imp) =>
              imp['f'] == flagName &&
              imp['k'] == exp['k'] &&
              imp['t'] == exp['t'] &&
              imp['c'] == exp['c'] &&
              imp['r'] == exp['r'] &&
              imp['b'] == exp['b']);

          expect(match, isNotEmpty,
              reason: 'Missing impression for "$testName": $exp');

          final actual = match.first;
          expect(actual['m'], isA<int>(),
              reason: 'Timestamp must be int for "$testName"');
          expect((actual['m'] as int) > 0, isTrue,
              reason: 'Timestamp must be > 0 for "$testName"');
        }
      });
    });
  }
}
