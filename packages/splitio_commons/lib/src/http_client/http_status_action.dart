/// Shared HTTP status taxonomy (spec §10.3), used by feeds, recorders, auth,
/// and streaming to decide how to react to an HTTP response status.
///
/// This is a **pure** classification with no I/O: it maps a raw status code to
/// a policy action. Callers (fetchers, the auth provider, the streaming FSM,
/// etc.) own the actual reaction (retry/backoff, token invalidate/reconnect,
/// stop) — this file only names the category. Keeping it pure makes it
/// trivially testable and reusable across every layer that speaks HTTP.
enum HttpStatusAction {
  /// `200 OK` — apply the response body.
  apply,

  /// `304 Not Modified` — no-op, keep the current cursor.
  notModified,

  /// `401` / `403` — auth failure. Auth → `SINGLE_SYNC`; streaming → token
  /// invalidate + reconnect (spec §11.3).
  authFailure,

  /// `414` — URI too long (e.g. too many flag sets). Non-retryable; log.
  uriTooLong,

  /// `429` / `5xx` — transient. Retry with backoff.
  transientRetry,

  /// Any other `4xx` (or otherwise unhandled non-2xx) — client error,
  /// non-retryable (`DO_NOT_RETRY`).
  doNotRetry,
}

/// Classifies an HTTP [statusCode] into a [HttpStatusAction] per the spec §10.3
/// taxonomy (shared by feeds, recorders, auth, streaming).
///
/// Pure function — no side effects, no I/O.
///
/// | Status        | Action           |
/// |---------------|------------------|
/// | `200`         | `apply`          |
/// | `304`         | `notModified`    |
/// | `401` / `403` | `authFailure`    |
/// | `414`         | `uriTooLong`     |
/// | `429` / `5xx` | `transientRetry` |
/// | other `4xx`   | `doNotRetry`     |
HttpStatusAction classifyStatus(int statusCode) {
  switch (statusCode) {
    case 200:
      return HttpStatusAction.apply;
    case 304:
      return HttpStatusAction.notModified;
    case 401:
    case 403:
      return HttpStatusAction.authFailure;
    case 414:
      return HttpStatusAction.uriTooLong;
    case 429:
      return HttpStatusAction.transientRetry;
  }
  // 5xx (and any status >= 500) is transient.
  if (statusCode >= 500) {
    return HttpStatusAction.transientRetry;
  }
  // Any other 4xx is a non-retryable client error.
  if (statusCode >= 400) {
    return HttpStatusAction.doNotRetry;
  }
  // Any other 2xx (201/202/204/206/…) is success. §10.3 only lists 200, but is
  // silent on other 2xx; HTTP semantics make all 2xx success, so apply.
  if (statusCode >= 200 && statusCode < 300) {
    return HttpStatusAction.apply;
  }
  // Any other status (1xx, 3xx other than 304) is not part of the §10.3
  // taxonomy's happy/retry paths — treat as non-retryable so a caller never
  // loops forever on an unexpected status.
  return HttpStatusAction.doNotRetry;
}
