import 'package:splitio_commons/src/auth/auth.dart';

/// Builds the SSE connect URI and redacts tokens for logging (spec §19.3).
///
/// Pure and stateless: it holds only the streaming base URI and the Ably API
/// version, so it is fully deterministic and unit-testable in isolation.
class SseUriBuilder {
  final Uri _streamingBaseUri;
  final String _ablyApiVersion;

  const SseUriBuilder({
    required Uri streamingBaseUri,
    String ablyApiVersion = '1.1',
  })  : _streamingBaseUri = streamingBaseUri,
        _ablyApiVersion = ablyApiVersion;

  /// Builds the SSE connect URI (spec §19.3):
  /// `{streaming}/sse?channels=<csv>&accessToken=<token>&v=<ver>&heartbeats=true`.
  Uri build(JwtCredential jwt) {
    final base = _streamingBaseUri;
    final path = base.path.endsWith('/sse')
        ? base.path
        : '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/sse';
    return base.replace(
      path: path,
      queryParameters: <String, String>{
        'channels': jwt.channels.join(','),
        'accessToken': jwt.token,
        'v': _ablyApiVersion,
        'heartbeats': 'true',
      },
    );
  }

  /// Renders [uri] for logs with the `accessToken` query param redacted, so a
  /// JWT never lands in log output.
  String redactToken(Uri uri) {
    if (!uri.queryParameters.containsKey('accessToken')) return uri.toString();
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'accessToken': '<redacted>',
      },
    ).toString();
  }
}
