# splitio_commons

Shared components of the Split Dart SDK — domain types, targeting engine, the client
evaluation and track pipeline, sync (polling and streaming), auth, HTTP client, storage,
impressions, event tracking, observability, and logging.

This package is a building block. If you are integrating Split into an application,
install `splitio_client_side` (Dart and Flutter apps, one user per client) or
`splitio_server_side` (Dart VM servers, key passed on every call) instead — both
depend on this package and expose the public SDK API.

## Requirements

- Dart SDK `>=3.0.0 <4.0.0`
- Supports Dart VM and Flutter (Android, iOS, Web, Desktop)

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
