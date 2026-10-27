import 'package:splitio_commons/src/client/basic_split_client.dart';
import 'package:test/test.dart';

/// A minimal conforming implementation used to prove subtype compliance at
/// compile time. If someone renames a method on [BasicSplitClient], this
/// file stops compiling — which is exactly what we want.
class _ConformingImpl implements BasicSplitClient {
  @override
  Future<void> whenReady() async {}

  @override
  Future<void> whenTimeout() async {}

  @override
  Stream<List<String>> whenUpdated() => const Stream.empty();

  @override
  Future<void> flush() async {}

  @override
  Future<void> destroy() async {}
}

void main() {
  group('BasicSplitClient (commons shared lifecycle interface)', () {
    test('exposes the five lifecycle methods', () {
      final BasicSplitClient client = _ConformingImpl();
      expect(client.whenReady, isA<Future<void> Function()>());
      expect(client.whenTimeout, isA<Future<void> Function()>());
      expect(client.whenUpdated, isA<Stream<List<String>> Function()>());
      expect(client.flush, isA<Future<void> Function()>());
      expect(client.destroy, isA<Future<void> Function()>());
    });

    test('is an abstract interface class (implementable but not extendable)',
        () {
      final BasicSplitClient client = _ConformingImpl();
      expect(client, isA<BasicSplitClient>());
    });
  });
}
