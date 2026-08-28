import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:test/test.dart';

void main() {
  group('SplitHttpClient', () {
    group('GET requests', () {
      test('sends Authorization header with Bearer token', () async {
        http.Request? captured;
        final mock = MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'my-key', client: mock);

        await client.get('https://api.example.com/test');

        expect(captured!.headers['Authorization'], 'Bearer my-key');
        client.close();
      });

      test('sends SplitSDKVersion header', () async {
        http.Request? captured;
        final mock = MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        await client.get('https://api.example.com/test');

        expect(captured!.headers['SplitSDKVersion'], 'dart_st-1.0.0');
        client.close();
      });

      test('appends query parameters to URL', () async {
        Uri? capturedUri;
        final mock = MockClient((request) async {
          capturedUri = request.url;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        await client.get(
          'https://api.example.com/splitChanges',
          queryParameters: {'since': '123', 's': '1.3'},
        );

        expect(capturedUri!.queryParameters['since'], '123');
        expect(capturedUri!.queryParameters['s'], '1.3');
        client.close();
      });

      test('returns status code, body, and headers', () async {
        final mock = MockClient((_) async {
          return http.Response(
            '{"splits":[]}',
            200,
            headers: {'x-custom': 'value'},
          );
        });
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        final response = await client.get('https://api.example.com/test');

        expect(response.statusCode, 200);
        expect(response.body, '{"splits":[]}');
        expect(response.headers['x-custom'], 'value');
        client.close();
      });

      test('merges extraHeaders with default headers', () async {
        http.Request? captured;
        final mock = MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        await client.get(
          'https://api.example.com/test',
          extraHeaders: const {'Cache-Control': 'no-cache'},
        );

        expect(captured!.headers['Cache-Control'], 'no-cache');
        expect(captured!.headers['Authorization'], 'Bearer key');
        expect(captured!.headers['SplitSDKVersion'], 'dart_st-1.0.0');
        client.close();
      });

      test('omits extraHeaders when none provided', () async {
        http.Request? captured;
        final mock = MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        await client.get('https://api.example.com/test');

        expect(captured!.headers.containsKey('Cache-Control'), isFalse);
        client.close();
      });

      test('propagates non-200 status codes', () async {
        final mock = MockClient((_) async => http.Response('Not Found', 404));
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        final response = await client.get('https://api.example.com/missing');

        expect(response.statusCode, 404);
        expect(response.body, 'Not Found');
        client.close();
      });
    });

    group('POST requests', () {
      test('sends Content-Type application/json header', () async {
        http.Request? captured;
        final mock = MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        await client.post('https://api.example.com/events', body: {'a': 1});

        expect(captured!.headers['Content-Type'], contains('application/json'));
        client.close();
      });

      test('JSON-encodes the body', () async {
        String? capturedBody;
        final mock = MockClient((request) async {
          capturedBody = request.body;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        final payload = {
          'events': [1, 2, 3]
        };
        await client.post('https://api.example.com/events', body: payload);

        expect(jsonDecode(capturedBody!), payload);
        client.close();
      });

      test('sends null body when not provided', () async {
        String? capturedBody;
        final mock = MockClient((request) async {
          capturedBody = request.body;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'key', client: mock);

        await client.post('https://api.example.com/events');

        expect(capturedBody, isEmpty);
        client.close();
      });

      test('includes Authorization header', () async {
        http.Request? captured;
        final mock = MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        });
        final client = SplitHttpClient(apiKey: 'secret', client: mock);

        await client.post('https://api.example.com/events');

        expect(captured!.headers['Authorization'], 'Bearer secret');
        client.close();
      });
    });

    group('SplitHttpResponse', () {
      test('stores all fields', () {
        const response = SplitHttpResponse(
          statusCode: 201,
          body: 'created',
          headers: {'location': '/new'},
        );

        expect(response.statusCode, 201);
        expect(response.body, 'created');
        expect(response.headers['location'], '/new');
      });
    });
  });
}
