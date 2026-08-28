import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'mock_backend.dart';

void main() {
  group('MockBackend.stubFromFixtures', () {
    late MockBackend backend;
    late HttpClient client;

    setUp(() async {
      backend = MockBackend();
      await backend.start();
    });

    tearDown(() async {
      client.close(force: true);
      await backend.shutdown();
    });

    test('serves split_changes.json at /splitChanges', () async {
      final suiteDir =
          '${Directory.current.path}/test/shared_data/basic_evaluation_suite';
      backend.stubFromFixtures(suiteDir);
      client = HttpClient();

      final req = await client.getUrl(Uri.parse('${backend.url}splitChanges'));
      final resp = await req.close();
      final body =
          jsonDecode(await utf8.decodeStream(resp)) as Map<String, dynamic>;

      expect(resp.statusCode, 200);
      expect(body['ff'], isNotNull);
      expect(body['ff']['d'], isList);
    });

    test('serves segment file at /memberships/:key', () async {
      final suiteDir =
          '${Directory.current.path}/test/shared_data/basic_evaluation_suite';
      backend.stubFromFixtures(suiteDir);
      client = HttpClient();

      final req =
          await client.getUrl(Uri.parse('${backend.url}memberships/user_c'));
      final resp = await req.close();
      final body =
          jsonDecode(await utf8.decodeStream(resp)) as Map<String, dynamic>;

      expect(resp.statusCode, 200);
      expect(body['ms'], isNotNull);
    });

    test('returns correct segment memberships for user_c (in beta_users)',
        () async {
      final suiteDir =
          '${Directory.current.path}/test/shared_data/basic_evaluation_suite';
      backend.stubFromFixtures(suiteDir);
      client = HttpClient();

      final req =
          await client.getUrl(Uri.parse('${backend.url}memberships/user_c'));
      final resp = await req.close();
      final body =
          jsonDecode(await utf8.decodeStream(resp)) as Map<String, dynamic>;

      expect(resp.statusCode, 200);
      expect(body['ms']['k'], contains('beta_users'));
      expect(body['ms']['cn'], 1000);
      expect(body['ls']['k'], isEmpty);
    });

    test('returns empty segment memberships for non-member user', () async {
      final suiteDir =
          '${Directory.current.path}/test/shared_data/basic_evaluation_suite';
      backend.stubFromFixtures(suiteDir);
      client = HttpClient();

      final req =
          await client.getUrl(Uri.parse('${backend.url}memberships/user_a'));
      final resp = await req.close();
      final body =
          jsonDecode(await utf8.decodeStream(resp)) as Map<String, dynamic>;

      expect(resp.statusCode, 200);
      expect(body['ms']['k'], isEmpty);
      expect(body['ms']['cn'], 1000);
    });

    test('captures POST /impressions', () async {
      final suiteDir =
          '${Directory.current.path}/test/shared_data/basic_evaluation_suite';
      backend.stubFromFixtures(suiteDir);
      client = HttpClient();

      final req =
          await client.postUrl(Uri.parse('${backend.url}testImpressions/bulk'));
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode([
        {'f': 'flag1'}
      ]));
      final resp = await req.close();
      await resp.drain();

      expect(resp.statusCode, 200);
      expect(backend.impressionRequests, hasLength(1));
    });
  });
}
