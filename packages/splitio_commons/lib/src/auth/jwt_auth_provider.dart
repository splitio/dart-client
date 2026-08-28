import 'dart:async';
import 'dart:convert';

import 'package:splitio_commons/src/http_client/http_client.dart';
import 'package:splitio_commons/src/logger/logger.dart';
import 'package:splitio_commons/src/models/models.dart';

import 'auth_provider.dart';
import 'credential.dart';

/// [AuthProvider] that fetches, decodes and caches the streaming JWT
/// (spec §6, §11.3, §19.3).
///
/// Credentials are provisioned **on-demand**: [credential] returns the cached
/// [JwtCredential] while it is still valid (`now < expiresAt − expiryBuffer`),
/// otherwise it fetches a fresh JWT from `GET {authUrl}/v2/auth?s=1.3`. This
/// provider owns **no timer**: the periodic proactive refresh (at
/// `expiresAt − refreshLeadTime`) is owned by the streaming runtime
/// (`StreamingManager`, §11.3), which reconnects to pull a fresh JWT. Expiry
/// mid-connection is handled reactively by the FSM via [invalidate] + reconnect.
///
/// The auth-fetch request itself is authenticated with the static
/// `Bearer <sdkKey>` credential. This provider relies on the injected
/// [SplitHttpClient], which already attaches that header on every request.
///
/// ## Failure representation (spec §10.3, §11.3)
///
/// A `401`/`403` from `/v2/auth` (auth failure → `SINGLE_SYNC`) and a
/// `pushEnabled == false` response are represented identically: a cached
/// [JwtCredential] with `pushEnabled == false`, an empty token and no channels.
/// Per spec §11.3 `pushEnabled == false` MUST mean **poll only**, so the caller
/// treats either as "no push". The negative result is cached so repeated
/// [credential] calls do not hammer `/v2/auth`; [invalidate]/[clearAll] clear it
/// to allow a retry at the next (re)connect.
///
/// A malformed JWT body or missing mandatory claims is surfaced the same way
/// (poll-only credential) rather than throwing, keeping auth off the readiness
/// critical path (spec §8.2).
class JwtAuthProvider implements AuthProvider {
  /// Ably API version reported by the auth request (`?s=1.3`).
  static const String _authApiVersion = '1.3';

  /// Fallback TTL applied when the JWT carries no `exp` claim (spec §19.3).
  static const int _fallbackTtlSeconds = 3600;

  final SplitHttpClient _httpClient;
  final String _authUrl;
  final int _expiryBufferSeconds;
  final DateTime Function() _now;
  final List<String> Function() _activeKeys;
  final SplitLogger _log;

  JwtCredential? _cached;
  Future<JwtCredential>? _inFlight;

  /// Creates a JWT auth provider.
  ///
  /// [httpClient] performs the `/v2/auth` fetch and MUST be constructed with the
  /// static SDK key so it attaches the `Bearer <sdkKey>` header (spec §19.3).
  /// [authUrl] is the auth base URL (e.g. `https://auth.split.io/api`).
  /// [expiryBufferSeconds] (default `60`, spec §19.3) is subtracted from
  /// `expiresAt` when deciding whether the cache is still valid. [now] is an
  /// injectable clock for testability (defaults to [DateTime.now]).
  ///
  /// [activeKeys] supplies the active matching keys (client-side); one repeated
  /// `users=<urlEncoded matchingKey>` query param is emitted per key (spec
  /// §19.3). Defaults to an empty list.
  JwtAuthProvider({
    required SplitHttpClient httpClient,
    required String authUrl,
    int expiryBufferSeconds = 60,
    DateTime Function()? now,
    List<String> Function()? activeKeys,
    SplitLogger? logger,
  })  : _httpClient = httpClient,
        _authUrl = authUrl,
        _expiryBufferSeconds = expiryBufferSeconds,
        _now = now ?? DateTime.now,
        _activeKeys = activeKeys ?? (() => const []),
        // Defaults to a silent logger (LogLevel.none) so constructing without a
        // logger — as existing callers/tests do — emits nothing.
        _log = logger ?? SplitLogger(level: LogLevel.none);

  @override
  Future<JwtCredential> credential(Target? target) {
    final cached = _cached;
    if (cached != null && _isValid(cached)) {
      return Future.value(cached);
    }
    // In-flight dedup: concurrent callers share the single fetch Future.
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final fetch = _fetch();
    _inFlight = fetch;
    return fetch.whenComplete(() {
      if (identical(_inFlight, fetch)) _inFlight = null;
    });
  }

  @override
  void invalidate(Target? target) {
    _cached = null;
  }

  @override
  void clearAll() {
    _cached = null;
    _inFlight = null;
  }

  /// A cached credential is valid while `now < expiresAt − expiryBuffer`.
  bool _isValid(JwtCredential credential) {
    final nowSeconds = _now().millisecondsSinceEpoch ~/ 1000;
    return nowSeconds < credential.expiresAt - _expiryBufferSeconds;
  }

  Future<JwtCredential> _fetch() async {
    final url = _buildAuthUrl();
    _log.debug('GET $url');
    try {
      final response = await _httpClient.get(url);
      _log.debug('Auth response: ${response.statusCode}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        // Auth failure (spec §10.3) → SINGLE_SYNC; cache poll-only so we do
        // not hammer /v2/auth. Cleared by invalidate()/clearAll().
        _log.warning(
            'Auth failed (${response.statusCode}): streaming disabled, '
            'falling back to polling. Check the SDK key and authUrl.');
        final result = _pollOnlyCredential();
        _cached = result;
        return result;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Semantic outcomes (pushEnabled=false, malformed JWT, missing claims)
        // are cached; see _parseResponse.
        final result = _parseResponse(response.body);
        _cached = result;
        if (result.pushEnabled) {
          _log.debug('Auth OK: push enabled, ${result.channels.length} '
              'channel(s), expires at ${result.expiresAt}');
        } else {
          _log.info('Auth OK but push disabled: falling back to polling.');
        }
        return result;
      }
      // 429 / 5xx and any other non-2xx are TRANSIENT (spec §10.3): retry with
      // backoff (FSM/transport's job). MUST NOT poison the cache — return a
      // poll-only credential for THIS call only, leaving _cached null so the
      // next credential() refetches.
      _log.warning('Auth returned transient status ${response.statusCode}: '
          'polling for now, will retry auth on next (re)connect.');
      return _pollOnlyCredential();
    } catch (e) {
      // Network/timeout error → transient; do not cache (see above).
      _log.warning('Auth request failed ($e): polling for now, will retry '
          'auth on next (re)connect.');
      return _pollOnlyCredential();
    }
  }

  /// Builds `{authUrl}/v2/auth?s=1.3` with one repeated `users=<matchingKey>`
  /// query param per active matching key (spec §19.3). Repeated multi-value
  /// params are used — not a comma-joined value — so the URL is built directly
  /// (SplitHttpClient.get only accepts a `Map<String,String>`).
  String _buildAuthUrl() {
    final buffer = StringBuffer('$_authUrl/v2/auth?s=$_authApiVersion');
    for (final key in _activeKeys()) {
      buffer.write('&users=${Uri.encodeQueryComponent(key)}');
    }
    return buffer.toString();
  }

  JwtCredential _parseResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      _log.warning('Auth body was not a JSON object: streaming disabled.');
      return _pollOnlyCredential();
    }

    final pushEnabled = decoded['pushEnabled'] == true;
    final token = decoded['token'];

    if (!pushEnabled || token is! String || token.isEmpty) {
      return _pollOnlyCredential();
    }

    final payload = _decodeJwtPayload(token);
    if (payload == null) {
      _log.warning('Auth JWT could not be decoded: streaming disabled.');
      return _pollOnlyCredential();
    }

    final channels = _parseChannels(payload['x-ably-capability']);
    final exp = payload['exp'];
    final nowSeconds = _now().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = exp is int
        ? exp
        : (exp is num ? exp.toInt() : nowSeconds + _fallbackTtlSeconds);

    // A valid token with no channels cannot receive push → poll only.
    if (channels.isEmpty) {
      _log.warning('Auth JWT carried no channels: streaming disabled.');
      return _pollOnlyCredential();
    }

    return JwtCredential(
      token: token,
      channels: channels,
      pushEnabled: true,
      expiresAt: expiresAt,
      connDelaySeconds: 0,
    );
  }

  /// Poll-only credential: streaming disabled (spec §11.3). Cached to avoid
  /// re-hitting `/v2/auth`; cleared by [invalidate]/[clearAll].
  JwtCredential _pollOnlyCredential() {
    final nowSeconds = _now().millisecondsSinceEpoch ~/ 1000;
    return JwtCredential(
      token: '',
      channels: const [],
      pushEnabled: false,
      expiresAt: nowSeconds + _fallbackTtlSeconds,
      connDelaySeconds: 0,
    );
  }

  /// Base64url-decodes the JWT payload (middle segment). Returns `null` on any
  /// structural or decode error.
  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      // Restore base64url padding.
      final remainder = payload.length % 4;
      if (remainder != 0)
        payload = payload.padRight(payload.length + (4 - remainder), '=');
      final decoded = utf8.decode(base64Url.decode(payload));
      final json = jsonDecode(decoded);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the channel set from the `x-ably-capability` claim, a JSON map of
  /// `channel → [actions]` (spec §19.3). The claim value MAY be a JSON string
  /// (needs a second decode) or an already-decoded map. Channel names are the
  /// map keys.
  List<String> _parseChannels(Object? capability) {
    Object? cap = capability;
    if (cap is String) {
      try {
        cap = jsonDecode(cap);
      } catch (_) {
        return const [];
      }
    }
    if (cap is Map) {
      return cap.keys.map((k) => k.toString()).toList();
    }
    return const [];
  }
}
