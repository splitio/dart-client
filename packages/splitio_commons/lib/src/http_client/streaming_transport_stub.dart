import 'streaming_transport.dart';

/// Fallback used when neither `dart:io` nor `dart:html` is available.
///
/// Exists so the conditional import in `streaming_transport_factory.dart`
/// compiles on every target. Any platform without a real streaming transport
/// throws on use rather than at compile time.
StreamingTransport createStreamingTransport() =>
    throw UnsupportedError('No streaming transport for this platform');
