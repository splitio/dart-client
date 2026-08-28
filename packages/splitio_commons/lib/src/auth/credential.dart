/// Base credential type carrying the ready-to-attach authorization header.
///
/// Every HTTP request attaches [authHeader] as its `Authorization` header
/// value (spec §6, §16). For data feeds, recorders and auth-fetch this is
/// `Bearer <sdkKey>`; for streaming it is the JWT (see [JwtCredential]).
class Credential {
  /// The ready-to-attach `Authorization` header value.
  final String authHeader;

  const Credential({required this.authHeader});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Credential &&
          runtimeType == other.runtimeType &&
          authHeader == other.authHeader;

  @override
  int get hashCode => authHeader.hashCode;

  @override
  String toString() => 'Credential(authHeader: $authHeader)';
}

/// Streaming credential produced by the JWT auth provider (spec §6, §16).
///
/// Extends [Credential] with the decoded JWT and its streaming metadata.
final class JwtCredential extends Credential {
  /// The raw JWT access token used for the SSE `accessToken` query param.
  final String token;

  /// The Ably channel set decoded from the JWT `x-ably-capability` claim.
  final List<String> channels;

  /// Whether streaming push is enabled. `false` MUST mean poll only.
  final bool pushEnabled;

  /// Token expiry, epoch **seconds** (from the JWT `exp` claim).
  final int expiresAt;

  /// Connection delay in seconds to apply before (re)connecting.
  final int connDelaySeconds;

  const JwtCredential({
    required this.token,
    required this.channels,
    required this.pushEnabled,
    required this.expiresAt,
    required this.connDelaySeconds,
    String? authHeader,
  }) : super(authHeader: authHeader ?? 'Bearer $token');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JwtCredential &&
          runtimeType == other.runtimeType &&
          authHeader == other.authHeader &&
          token == other.token &&
          _listEquals(channels, other.channels) &&
          pushEnabled == other.pushEnabled &&
          expiresAt == other.expiresAt &&
          connDelaySeconds == other.connDelaySeconds;

  @override
  int get hashCode => Object.hash(
        authHeader,
        token,
        Object.hashAll(channels),
        pushEnabled,
        expiresAt,
        connDelaySeconds,
      );

  @override
  String toString() =>
      'JwtCredential(authHeader: $authHeader, token: $token, channels: $channels, '
      'pushEnabled: $pushEnabled, expiresAt: $expiresAt, connDelaySeconds: $connDelaySeconds)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
