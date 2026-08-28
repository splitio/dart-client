import 'package:splitio_commons/src/auth/auth.dart';
import 'package:splitio_commons/src/sync/streaming/sse_uri_builder.dart';
import 'package:test/test.dart';

JwtCredential _jwt({
  List<String> channels = const ['ch1', 'ch2'],
  String token = 'the-token',
}) =>
    JwtCredential(
      token: token,
      channels: channels,
      pushEnabled: true,
      expiresAt: 0,
      connDelaySeconds: 0,
    );

void main() {
  group('SseUriBuilder.build', () {
    test('appends /sse and query params to a bare base', () {
      final builder = SseUriBuilder(
        streamingBaseUri: Uri.parse('https://streaming.example.com'),
      );
      final uri = builder.build(_jwt());
      expect(uri.path, '/sse');
      expect(uri.queryParameters['channels'], 'ch1,ch2');
      expect(uri.queryParameters['accessToken'], 'the-token');
      expect(uri.queryParameters['v'], '1.1');
      expect(uri.queryParameters['heartbeats'], 'true');
    });

    test('honors a custom Ably API version', () {
      final builder = SseUriBuilder(
        streamingBaseUri: Uri.parse('https://streaming.example.com'),
        ablyApiVersion: '2.0',
      );
      expect(builder.build(_jwt()).queryParameters['v'], '2.0');
    });

    test('does not double-append when base already ends with /sse', () {
      final builder = SseUriBuilder(
        streamingBaseUri: Uri.parse('https://streaming.example.com/sse'),
      );
      expect(builder.build(_jwt()).path, '/sse');
    });

    test('handles a base path ending with a trailing slash', () {
      final builder = SseUriBuilder(
        streamingBaseUri: Uri.parse('https://streaming.example.com/api/'),
      );
      expect(builder.build(_jwt()).path, '/api/sse');
    });

    test('preserves a non-slash-terminated sub path', () {
      final builder = SseUriBuilder(
        streamingBaseUri: Uri.parse('https://streaming.example.com/api'),
      );
      expect(builder.build(_jwt()).path, '/api/sse');
    });
  });

  group('SseUriBuilder.redactToken', () {
    test('replaces the accessToken query param with <redacted>', () {
      final builder = SseUriBuilder(
        streamingBaseUri: Uri.parse('https://streaming.example.com'),
      );
      final uri = builder.build(_jwt(token: 'secret'));
      final redacted = builder.redactToken(uri);
      expect(redacted, contains('accessToken=%3Credacted%3E'));
      expect(redacted, isNot(contains('secret')));
    });

    test('returns the uri unchanged when no accessToken present', () {
      final builder = SseUriBuilder(
        streamingBaseUri: Uri.parse('https://streaming.example.com'),
      );
      final uri = Uri.parse('https://x.example.com/sse?foo=bar');
      expect(builder.redactToken(uri), uri.toString());
    });
  });
}
