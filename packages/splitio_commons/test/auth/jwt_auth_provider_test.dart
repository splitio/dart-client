import 'dart:async';
import 'dart:convert';

import 'package:splitio_commons/src/auth/auth.dart';
import 'package:http/http.dart' as http;
import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:test/test.dart';

/// Hand fake for [http.Client] recording requests and returning queued
/// responses (matches the repo's fake-based test style).
class _FakeHttpClient extends http.BaseClient {
  final List<Uri> requestedUris = [];
  final List<Map<String, String>> requestedHeaders = [];

  /// Responder invoked per request; returns (statusCode, body).
  Future<(int, String)> Function(http.BaseRequest request) responder =
      (_) async => (200, '{}');

  int callCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    requestedUris.add(request.url);
    requestedHeaders.add(Map<String, String>.from(request.headers));
    final (status, body) = await responder(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

/// Builds a JWT `header.payload.signature` where [payload] is the claims map.
String _jwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) {
    final b = base64Url.encode(utf8.encode(jsonEncode(m)));
    return b.replaceAll('=', ''); // JWTs are unpadded.
  }

  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.sig';
}

String _authBody({
  required bool pushEnabled,
  String? token,
}) =>
    jsonEncode({
      'pushEnabled': pushEnabled,
      'token': token ?? '',
    });

void main() {
  const authUrl = 'https://auth.split.io/api';

  late _FakeHttpClient fake;
  late SplitHttpClient httpClient;
  DateTime now = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000);

  DateTime clock() => now;
  int nowSeconds() => now.millisecondsSinceEpoch ~/ 1000;

  List<String> activeKeys = const [];

  JwtAuthProvider newProvider({int expiryBufferSeconds = 60}) =>
      JwtAuthProvider(
        httpClient: httpClient,
        authUrl: authUrl,
        expiryBufferSeconds: expiryBufferSeconds,
        now: clock,
        activeKeys: () => activeKeys,
      );

  setUp(() {
    now = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000);
    activeKeys = const [];
    fake = _FakeHttpClient();
    httpClient = SplitHttpClient(apiKey: 'sdk-key-123', client: fake);
  });

  group('JwtAuthProvider — successful fetch', () {
    test('parses token, channels, expiresAt and pushEnabled', () async {
      final exp = nowSeconds() + 3600;
      final token = _jwt({
        'x-ably-capability': jsonEncode({
          'channel-a': ['subscribe'],
          'channel-b': ['subscribe'],
        }),
        'iat': nowSeconds(),
        'exp': exp,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final provider = newProvider();
      final cred = await provider.credential(null);

      expect(cred.pushEnabled, isTrue);
      expect(cred.token, equals(token));
      expect(cred.authHeader, equals('Bearer $token'));
      expect(cred.channels, equals(['channel-a', 'channel-b']));
      expect(cred.expiresAt, equals(exp));
    });

    test('requests GET {authUrl}/v2/auth?s=1.3 with the static Bearer header',
        () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': nowSeconds() + 3600,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      await newProvider().credential(null);

      final uri = fake.requestedUris.single;
      expect(uri.path, equals('/api/v2/auth'));
      expect(uri.queryParameters['s'], equals('1.3'));
      expect(fake.requestedHeaders.single['Authorization'],
          equals('Bearer sdk-key-123'));
    });

    test('accepts x-ably-capability as an already-decoded map', () async {
      final token = _jwt({
        'x-ably-capability': {
          'ch1': ['subscribe'],
        },
        'exp': nowSeconds() + 3600,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final cred = await newProvider().credential(null);
      expect(cred.channels, equals(['ch1']));
    });

    test('falls back to TTL 3600 when exp claim is absent', () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final cred = await newProvider().credential(null);
      expect(cred.expiresAt, equals(nowSeconds() + 3600));
    });
  });

  group('JwtAuthProvider — caching & expiry', () {
    test('second call within validity does NOT refetch', () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': nowSeconds() + 3600,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final provider = newProvider();
      final first = await provider.credential(null);
      final second = await provider.credential(null);

      expect(fake.callCount, equals(1));
      expect(identical(first, second), isTrue);
    });

    test('call after expiresAt − buffer refetches', () async {
      final exp = nowSeconds() + 100;
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': exp,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final provider = newProvider(); // buffer 60
      await provider.credential(null);
      expect(fake.callCount, equals(1));

      // Advance past exp - buffer (100 - 60 = 40s window).
      now = now.add(const Duration(seconds: 45));
      await provider.credential(null);
      expect(fake.callCount, equals(2));
    });

    test('call just before expiresAt − buffer still uses cache', () async {
      final exp = nowSeconds() + 100;
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': exp,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final provider = newProvider();
      await provider.credential(null);
      now = now.add(const Duration(seconds: 39)); // still < 40
      await provider.credential(null);
      expect(fake.callCount, equals(1));
    });
  });

  group('JwtAuthProvider — invalidate & clearAll', () {
    test('invalidate forces a refetch on next credential()', () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': nowSeconds() + 3600,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final provider = newProvider();
      await provider.credential(null);
      provider.invalidate(null);
      await provider.credential(null);
      expect(fake.callCount, equals(2));
    });

    test('clearAll drops cache and forces a refetch', () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': nowSeconds() + 3600,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final provider = newProvider();
      await provider.credential(null);
      provider.clearAll();
      await provider.credential(null);
      expect(fake.callCount, equals(2));
    });
  });

  group('JwtAuthProvider — in-flight dedup', () {
    test('two concurrent calls trigger only one HTTP fetch', () async {
      final completer = Completer<void>();
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': nowSeconds() + 3600,
      });
      fake.responder = (_) async {
        await completer.future;
        return (200, _authBody(pushEnabled: true, token: token));
      };

      final provider = newProvider();
      final f1 = provider.credential(null);
      final f2 = provider.credential(null);
      completer.complete();

      final r1 = await f1;
      final r2 = await f2;

      expect(fake.callCount, equals(1));
      expect(identical(r1, r2), isTrue);
    });

    test('a new fetch is allowed after the in-flight one completes', () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': nowSeconds() + 3600,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final provider = newProvider();
      await provider.credential(null);
      provider.invalidate(null);
      await provider.credential(null);
      expect(fake.callCount, equals(2));
    });
  });

  group('JwtAuthProvider — pushEnabled=false & auth failures', () {
    test('pushEnabled=false yields a poll-only credential', () async {
      fake.responder = (_) async => (200, _authBody(pushEnabled: false));

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
      expect(cred.token, isEmpty);
      expect(cred.channels, isEmpty);
      expect(cred.authHeader, equals('Bearer '));
    });

    test('401 yields a poll-only credential', () async {
      fake.responder = (_) async => (401, '{"error":"unauthorized"}');

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
      expect(cred.channels, isEmpty);
    });

    test('403 yields a poll-only credential', () async {
      fake.responder = (_) async => (403, 'forbidden');

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('500 yields a poll-only credential (transient, not cached)', () async {
      fake.responder = (_) async => (500, 'boom');

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('429 yields a poll-only credential (transient, not cached)', () async {
      fake.responder = (_) async => (429, 'too many');

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('network error yields a poll-only credential (transient)', () async {
      fake.responder = (_) async => throw Exception('network down');

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('401 poll-only credential IS cached (not refetched within validity)',
        () async {
      fake.responder = (_) async => (401, 'nope');

      final provider = newProvider();
      await provider.credential(null);
      await provider.credential(null);
      expect(fake.callCount, equals(1));
    });

    test('403 poll-only credential IS cached', () async {
      fake.responder = (_) async => (403, 'nope');

      final provider = newProvider();
      await provider.credential(null);
      await provider.credential(null);
      expect(fake.callCount, equals(1));
    });

    test('500 then 2xx: transient NOT cached → second call refetches success',
        () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': nowSeconds() + 3600,
      });
      var first = true;
      fake.responder = (_) async {
        if (first) {
          first = false;
          return (500, 'boom');
        }
        return (200, _authBody(pushEnabled: true, token: token));
      };

      final provider = newProvider();
      final c1 = await provider.credential(null);
      expect(c1.pushEnabled, isFalse);
      final c2 = await provider.credential(null);
      expect(c2.pushEnabled, isTrue);
      expect(fake.callCount, equals(2));
    });

    test('network error then success: transient NOT cached → refetch succeeds',
        () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({'ch': <String>[]}),
        'exp': nowSeconds() + 3600,
      });
      var first = true;
      fake.responder = (_) async {
        if (first) {
          first = false;
          throw Exception('network down');
        }
        return (200, _authBody(pushEnabled: true, token: token));
      };

      final provider = newProvider();
      final c1 = await provider.credential(null);
      expect(c1.pushEnabled, isFalse);
      final c2 = await provider.credential(null);
      expect(c2.pushEnabled, isTrue);
      expect(fake.callCount, equals(2));
    });
  });

  group('JwtAuthProvider — users query param (spec §19.3)', () {
    test('emits one repeated users param per active matching key', () async {
      activeKeys = const ['user_1', 'user_2'];
      fake.responder = (_) async => (401, 'x');

      await newProvider().credential(null);

      final uri = fake.requestedUris.single;
      expect(uri.queryParameters['s'], equals('1.3'));
      expect(uri.queryParametersAll['users'], equals(['user_1', 'user_2']));
    });

    test('emits no users param when there are zero active keys', () async {
      activeKeys = const [];
      fake.responder = (_) async => (401, 'x');

      await newProvider().credential(null);

      final uri = fake.requestedUris.single;
      expect(uri.queryParametersAll.containsKey('users'), isFalse);
    });

    test('url-encodes matching keys with special characters', () async {
      activeKeys = const ['a b&c', 'x/y'];
      fake.responder = (_) async => (401, 'x');

      await newProvider().credential(null);

      final uri = fake.requestedUris.single;
      expect(uri.queryParametersAll['users'], equals(['a b&c', 'x/y']));
    });
  });

  group('JwtAuthProvider — malformed JWT / claims', () {
    test('pushEnabled=true but empty token → poll only', () async {
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: ''));

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('token with wrong number of segments → poll only', () async {
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: 'not-a-jwt'));

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('non-base64 payload segment → poll only', () async {
      fake.responder = (_) async => (
            200,
            _authBody(pushEnabled: true, token: 'aaa.!!!not-base64!!!.ccc')
          );

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('payload not a JSON object → poll only', () async {
      final seg = base64Url.encode(utf8.encode('[1,2,3]')).replaceAll('=', '');
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: 'h.$seg.s'));

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('missing x-ably-capability (no channels) → poll only', () async {
      final token = _jwt({'exp': nowSeconds() + 3600});
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
      expect(cred.channels, isEmpty);
    });

    test('response body is not a JSON object → poll only', () async {
      fake.responder = (_) async => (200, '"just a string"');

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('response body is invalid JSON → poll only', () async {
      fake.responder = (_) async => (200, '{not json');

      final cred = await newProvider().credential(null);
      expect(cred.pushEnabled, isFalse);
    });

    test('x-ably-capability as unparseable string → poll only', () async {
      final token = _jwt({
        'x-ably-capability': '{not json',
        'exp': nowSeconds() + 3600,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));

      final cred = await newProvider().credential(null);
      expect(cred.channels, isEmpty);
      expect(cred.pushEnabled, isFalse);
    });
  });

  group('JwtAuthProvider — logging', () {
    // Runs [body] capturing everything the logger prints, and returns the
    // captured lines.
    Future<List<String>> captureLogs(Future<void> Function() body) async {
      final lines = <String>[];
      await runZoned(
        body,
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => lines.add(line),
        ),
      );
      return lines;
    }

    JwtAuthProvider verboseProvider() => JwtAuthProvider(
          httpClient: httpClient,
          authUrl: authUrl,
          now: clock,
          activeKeys: () => activeKeys,
          logger: SplitLogger(level: LogLevel.verbose),
        );

    test('auth failure (403) logs a warning naming the fallback', () async {
      fake.responder = (_) async => (403, 'forbidden');
      final logs = await captureLogs(() => verboseProvider().credential(null));
      expect(
        logs.any((l) =>
            l.contains('[WARNING]') &&
            l.contains('Auth failed (403)') &&
            l.contains('polling')),
        isTrue,
        reason: 'expected a warning about auth failure, got: $logs',
      );
    });

    test('transient status (500) logs a retry warning', () async {
      fake.responder = (_) async => (500, 'boom');
      final logs = await captureLogs(() => verboseProvider().credential(null));
      expect(
        logs.any((l) =>
            l.contains('[WARNING]') && l.contains('transient status 500')),
        isTrue,
        reason: 'expected a transient-status warning, got: $logs',
      );
    });

    test('successful push-enabled fetch logs the request and OK', () async {
      final token = _jwt({
        'x-ably-capability': jsonEncode({
          'chan': ['subscribe'],
        }),
        'exp': nowSeconds() + 3600,
      });
      fake.responder =
          (_) async => (200, _authBody(pushEnabled: true, token: token));
      final logs = await captureLogs(() => verboseProvider().credential(null));
      expect(logs.any((l) => l.contains('GET $authUrl/v2/auth')), isTrue);
      expect(
        logs.any((l) => l.contains('Auth OK') && l.contains('push enabled')),
        isTrue,
        reason: 'expected an auth-OK debug line, got: $logs',
      );
    });

    test('silent by default (no logger) emits nothing', () async {
      fake.responder = (_) async => (403, 'forbidden');
      final logs = await captureLogs(() => newProvider().credential(null));
      expect(logs, isEmpty);
    });
  });

  test('implements AuthProvider', () async {
    final AuthProvider provider = newProvider();
    fake.responder = (_) async => (401, 'x');
    final cred = await provider.credential(null);
    expect(cred, isA<JwtCredential>());
  });
}
