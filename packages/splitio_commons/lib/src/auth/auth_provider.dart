import 'package:splitio_commons/src/models/models.dart';

import 'credential.dart';

/// Per-endpoint credential provisioning port (spec §6).
///
/// Credentials are provisioned **on-demand**: [credential] fetches or returns a
/// cached credential as needed. An [AuthProvider] MUST NOT run a periodic
/// refresh task itself (spec §6, §11.3) — the provider refresh is reactive (e.g.
/// on `401` via [invalidate]). The periodic proactive token refresh is owned by
/// the streaming runtime (`StreamingManager`, §11.3), not by this provider.
abstract class AuthProvider {
  /// Returns the credential for [target], fetching or reusing a cached value as
  /// needed. [target] MAY be `null` for endpoints that are not per-target
  /// (data feeds, recorders, auth-fetch).
  Future<Credential> credential(Target? target);

  /// Drops the cached credential for [target] (e.g. on a `401`). No-op for
  /// providers that hold no cache (e.g. [StaticKeyAuthProvider]).
  void invalidate(Target? target);

  /// Drops all cached credentials. No-op for providers that hold no cache.
  void clearAll();
}

/// [AuthProvider] backed by a fixed `Authorization` header value (spec §6).
///
/// Used for data feeds, recorders and auth-fetch, where the header is
/// `Bearer <sdkKey>`. Holds no cache, so [invalidate] and [clearAll] are
/// no-ops.
class StaticKeyAuthProvider implements AuthProvider {
  final Credential _credential;

  /// Creates a provider that always returns [authHeader] as the credential's
  /// `Authorization` header. Per spec §6 this is `"Bearer <sdkKey>"`.
  StaticKeyAuthProvider(String authHeader)
      : _credential = Credential(authHeader: authHeader);

  @override
  Future<Credential> credential(Target? target) async => _credential;

  @override
  void invalidate(Target? target) {}

  @override
  void clearAll() {}
}
