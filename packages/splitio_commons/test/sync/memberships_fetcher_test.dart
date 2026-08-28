import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/parsing/parsing.dart';
import 'package:splitio_commons/src/storage/storage.dart';
import 'package:splitio_commons/src/sync/sync.dart';
import 'package:test/test.dart';

const _membershipsResponse = '''
{
  "ms": {
    "k": ["segment_a", "segment_b"],
    "cn": 50
  }
}
''';

const _membershipsWithLargeSegments = '''
{
  "ms": {
    "k": ["segment_a"],
    "cn": 10
  },
  "ls": {
    "k": ["large_seg_1"],
    "cn": 20
  }
}
''';

MembershipsFetcher _createFetcher({
  required SplitHttpClient httpClient,
  InMemoryMembershipStore? membershipStore,
}) {
  final effectiveStore = membershipStore ?? InMemoryMembershipStore();
  final processor = MembershipsProcessor(membershipStore: effectiveStore);
  return MembershipsFetcher(
    httpClient: httpClient,
    log: SplitLogger(level: LogLevel.none),
    baseUrl: 'https://sdk.split.io/api',
    processor: processor,
  );
}

void main() {
  group('MembershipsFetcher', () {
    test('fetch returns false when no key is bound', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{}', 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = _createFetcher(httpClient: httpClient);
      final result = await fetcher.fetch();

      expect(result, isFalse);
      httpClient.close();
    });

    test('fetch returns true and populates store after bindKey', () async {
      final mockClient = MockClient((request) async {
        return http.Response(_membershipsResponse, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final store = InMemoryMembershipStore();

      final fetcher = _createFetcher(
        httpClient: httpClient,
        membershipStore: store,
      );
      fetcher.bindKey('user1');

      final result = await fetcher.fetch();

      expect(result, isTrue);
      expect(store.isInSegment('segment_a', 'user1'), isTrue);
      expect(store.isInSegment('segment_b', 'user1'), isTrue);
      expect(store.isInSegment('segment_c', 'user1'), isFalse);
      httpClient.close();
    });

    test('fetchForKey fetches for a specific key', () async {
      String? capturedPath;
      final mockClient = MockClient((request) async {
        capturedPath = request.url.path;
        return http.Response(_membershipsResponse, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final store = InMemoryMembershipStore();

      final fetcher = _createFetcher(
        httpClient: httpClient,
        membershipStore: store,
      );

      final result = await fetcher.fetchForKey('specific_user');

      expect(result, isTrue);
      expect(capturedPath, equals('/api/memberships/specific_user'));
      expect(store.isInSegment('segment_a', 'specific_user'), isTrue);
      httpClient.close();
    });

    test('fetch sends Cache-Control: no-cache header', () async {
      String? capturedCacheControl;
      final mockClient = MockClient((request) async {
        capturedCacheControl = request.headers['cache-control'];
        return http.Response(_membershipsResponse, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = _createFetcher(httpClient: httpClient);
      fetcher.bindKey('user1');
      await fetcher.fetch();

      expect(capturedCacheControl, equals('no-cache'));
      httpClient.close();
    });

    test('fetch returns false on non-200 response', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = _createFetcher(httpClient: httpClient);
      fetcher.bindKey('user1');

      final result = await fetcher.fetch();

      expect(result, isFalse);
      httpClient.close();
    });

    test('boundKeys accumulates bound keys', () async {
      final mockClient = MockClient((request) async {
        return http.Response(_membershipsResponse, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = _createFetcher(httpClient: httpClient);

      expect(fetcher.boundKeys, isEmpty);
      expect(fetcher.hasBoundKeys, isFalse);
      fetcher.bindKey('user1');
      expect(fetcher.boundKeys, equals({'user1'}));
      expect(fetcher.hasBoundKeys, isTrue);
      fetcher.bindKey('user2');
      expect(fetcher.boundKeys, equals({'user1', 'user2'}));

      httpClient.close();
    });

    test('fetch retries on exception and returns false after exhaustion',
        () async {
      var attempts = 0;
      final mockClient = MockClient((request) async {
        attempts++;
        throw Exception('connection refused');
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);

      final fetcher = MembershipsFetcher(
        httpClient: httpClient,
        log: SplitLogger(level: LogLevel.none),
        baseUrl: 'https://sdk.split.io/api',
        processor:
            MembershipsProcessor(membershipStore: InMemoryMembershipStore()),
        maxRetries: 2,
        baseBackoff: Duration.zero,
      );
      fetcher.bindKey('user1');

      final result = await fetcher.fetch();

      expect(result, isFalse);
      expect(attempts, equals(2));
      httpClient.close();
    });

    test('fetchForKey processes large segments', () async {
      final mockClient = MockClient((request) async {
        return http.Response(_membershipsWithLargeSegments, 200);
      });
      final httpClient =
          SplitHttpClient(apiKey: 'test-key', client: mockClient);
      final store = InMemoryMembershipStore();

      final fetcher = _createFetcher(
        httpClient: httpClient,
        membershipStore: store,
      );

      final result = await fetcher.fetchForKey('user1');

      expect(result, isTrue);
      expect(store.isInSegment('segment_a', 'user1'), isTrue);
      expect(store.isInSegment('large_seg_1', 'user1'), isTrue);
      httpClient.close();
    });
  });
}
