import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/sync.dart';
import 'package:test/test.dart';

const _splitChanges200 = '''
{
  "ff": {
    "t": 100,
    "s": -1,
    "d": [
      {
        "name": "flag_a",
        "trafficTypeName": "user",
        "killed": false,
        "defaultTreatment": "off",
        "conditions": [],
        "trafficAllocation": 100,
        "seed": 12345,
        "algo": 2,
        "changeNumber": 100,
        "status": "ACTIVE"
      }
    ]
  },
  "rbs": {
    "t": 50,
    "s": -1,
    "d": []
  }
}
''';

const _splitChangesEmpty = '''
{
  "ff": {"t": -1, "s": -1, "d": []},
  "rbs": {"t": -1, "s": -1, "d": []}
}
''';

FlagsFetcher _createFetcher({
  required SplitHttpClient httpClient,
  InMemoryRuleStore? ruleStore,
  InMemoryRuleBasedSegmentStore? rbsStore,
  void Function(List<String>)? onUpdate,
}) {
  final effectiveRuleStore = ruleStore ?? InMemoryRuleStore();
  final effectiveRbsStore = rbsStore ?? InMemoryRuleBasedSegmentStore();
  final processor = SplitChangeProcessor(
    parser: RuleParser(),
    ruleStore: effectiveRuleStore,
    rbsStore: effectiveRbsStore,
  );
  return FlagsFetcher(
    httpClient: httpClient,
    log: SplitLogger(level: LogLevel.none),
    baseUrl: 'https://sdk.split.io/api',
    processor: processor,
    ruleStore: effectiveRuleStore,
    rbsStore: effectiveRbsStore,
    onUpdate: onUpdate,
  );
}

void main() {
  group('FlagsFetcher', () {
    test('fetch returns true and populates store on 200', () async {
      final mockClient = MockClient((request) async {
        return http.Response(_splitChanges200, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final ruleStore = InMemoryRuleStore();
      final rbsStore = InMemoryRuleBasedSegmentStore();

      final fetcher = _createFetcher(
        httpClient: httpClient,
        ruleStore: ruleStore,
        rbsStore: rbsStore,
      );

      final result = await fetcher.fetch();

      expect(result, isTrue);
      expect(ruleStore.get('flag_a'), isNotNull);
      expect(ruleStore.changeNumber(), equals(100));
      expect(rbsStore.changeNumber(), equals(50));

      httpClient.close();
    });

    test('fetch returns true on 304 Not Modified', () async {
      final mockClient = MockClient((request) async {
        return http.Response('', 304);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = _createFetcher(httpClient: httpClient);
      final result = await fetcher.fetch();

      expect(result, isTrue);
      httpClient.close();
    });

    test('fetch returns false on server error after retries', () async {
      var attempts = 0;
      final mockClient = MockClient((request) async {
        attempts++;
        return http.Response('Internal Server Error', 500);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = FlagsFetcher(
        httpClient: httpClient,
        log: SplitLogger(level: LogLevel.none),
        baseUrl: 'https://sdk.split.io/api',
        processor: SplitChangeProcessor(
          parser: RuleParser(),
          ruleStore: InMemoryRuleStore(),
          rbsStore: InMemoryRuleBasedSegmentStore(),
        ),
        ruleStore: InMemoryRuleStore(),
        rbsStore: InMemoryRuleBasedSegmentStore(),
      );

      final result = await fetcher.fetch();

      expect(result, isFalse);
      expect(attempts, equals(1));
      httpClient.close();
    });

    test('fetch sends correct query parameters with since values', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(_splitChanges200, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final ruleStore = InMemoryRuleStore();
      final rbsStore = InMemoryRuleBasedSegmentStore();

      final fetcher = _createFetcher(
        httpClient: httpClient,
        ruleStore: ruleStore,
        rbsStore: rbsStore,
      );

      await fetcher.fetch();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.queryParameters['since'], equals('-1'));
      expect(capturedUri!.queryParameters['rbSince'], equals('-1'));
      expect(capturedUri!.queryParameters['s'], equals('1.3'));

      // Second fetch should use updated cursors
      await fetcher.fetch();
      expect(capturedUri!.queryParameters['since'], equals('100'));
      expect(capturedUri!.queryParameters['rbSince'], equals('50'));

      httpClient.close();
    });

    test('fetch sends Cache-Control: no-cache header', () async {
      String? capturedCacheControl;
      final mockClient = MockClient((request) async {
        capturedCacheControl = request.headers['cache-control'];
        return http.Response(_splitChanges200, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = _createFetcher(httpClient: httpClient);
      await fetcher.fetch();

      expect(capturedCacheControl, equals('no-cache'));
      httpClient.close();
    });

    test('fetch invokes onUpdate callback with changed flags', () async {
      final changedFlags = <List<String>>[];
      final mockClient = MockClient((request) async {
        return http.Response(_splitChanges200, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = _createFetcher(
        httpClient: httpClient,
        onUpdate: (flags) => changedFlags.add(flags),
      );

      await fetcher.fetch();

      expect(changedFlags, hasLength(1));
      expect(changedFlags.first, contains('flag_a'));
      httpClient.close();
    });

    test('fetch does not invoke onUpdate when no flags change', () async {
      final changedFlags = <List<String>>[];
      final mockClient = MockClient((request) async {
        return http.Response(_splitChangesEmpty, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = _createFetcher(
        httpClient: httpClient,
        onUpdate: (flags) => changedFlags.add(flags),
      );

      await fetcher.fetch();

      expect(changedFlags, isEmpty);
      httpClient.close();
    });

    test('fetch retries on exception and eventually returns false', () async {
      var attempts = 0;
      final mockClient = MockClient((request) async {
        attempts++;
        throw Exception('network error');
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = FlagsFetcher(
        httpClient: httpClient,
        log: SplitLogger(level: LogLevel.none),
        baseUrl: 'https://sdk.split.io/api',
        processor: SplitChangeProcessor(
          parser: RuleParser(),
          ruleStore: InMemoryRuleStore(),
          rbsStore: InMemoryRuleBasedSegmentStore(),
        ),
        ruleStore: InMemoryRuleStore(),
        rbsStore: InMemoryRuleBasedSegmentStore(),
        maxRetries: 2,
        baseBackoff: Duration.zero,
      );

      final result = await fetcher.fetch();

      expect(result, isFalse);
      expect(attempts, equals(2));
      httpClient.close();
    });
  });
}
