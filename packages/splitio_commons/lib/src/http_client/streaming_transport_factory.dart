/// Conditional-import selector for the platform-specific [StreamingTransport].
///
/// Resolves to the VM impl when `dart:io` is available, the web impl when
/// `dart:html` is available, and the throwing stub otherwise. Each platform
/// file defines the same `createStreamingTransport()` factory symbol.
export 'streaming_transport_stub.dart'
    if (dart.library.io) 'streaming_transport_io.dart'
    if (dart.library.html) 'streaming_transport_web.dart';
